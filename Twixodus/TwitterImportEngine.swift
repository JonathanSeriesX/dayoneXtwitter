import Foundation

struct TwitterImportEngine {
    private let fileManager = FileManager.default

    private struct TitleGenerationOutcome {
        let title: String
        let failureReason: String?
    }

    private struct LLMSummaryOutcome {
        let summary: String?
        let failureReason: String?
    }

    private struct QuoteReference {
        let handle: String
        let statusID: String
    }

    func resolveDrop(url: URL) throws -> ArchiveLocation {
        guard url.isFileURL else {
            throw ImportEngineError.droppedItemIsNotFileSystemURL
        }

        let resolved = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
            throw ImportEngineError.unsupportedDropType
        }

        if isDirectory.boolValue {
            return try resolveDirectoryDrop(directoryURL: resolved, sourceWasZip: false)
        }

        if resolved.pathExtension.lowercased() == "zip" {
            return try resolveZipDrop(zipURL: resolved)
        }

        throw ImportEngineError.unsupportedDropType
    }

    func prepareImportContext(archive: ArchiveLocation, settings: ImportSettings) throws -> PreparedImportContext {
        let statusesFileURL = archive.archiveRootURL.appendingPathComponent("processed_tweets.txt")
        let accountProfile = loadAccountProfile(
            from: archive.archiveRootURL
                .appendingPathComponent("data")
                .appendingPathComponent("account.js")
        )

        var tweets = try loadTweets(from: archive.tweetsJSURL)
        for index in tweets.indices {
            processTweetTextForMarkdownLinks(tweet: &tweets[index], archiveDataDirectory: archive.dataDirectoryURL)
        }

        let archiveUsername = accountProfile?.username?.trimmedNilIfEmpty
        let ownTweetIDs = Set(tweets.map(\.idStr))

        let allThreads = combineThreads(tweets: tweets)
        let range = dateRange(from: settings)

        let dateFilteredThreads = allThreads
            .filter { thread in
                guard let firstTweet = thread.first else { return false }
                return firstTweet.createdAt >= range.start && firstTweet.createdAt <= range.end
            }
            .sorted { lhs, rhs in
                guard let lhsFirst = lhs.first, let rhsFirst = rhs.first else {
                    return lhs.count < rhs.count
                }
                if lhsFirst.createdAt == rhsFirst.createdAt {
                    return numericTweetID(lhsFirst.idStr) < numericTweetID(rhsFirst.idStr)
                }
                return lhsFirst.createdAt < rhsFirst.createdAt
            }

        // Step 3 count should reflect import settings, not just date range.
        let filteredThreads = dateFilteredThreads.filter { thread in
            guard !thread.isEmpty else { return false }
            var mutableThread = thread
            let category = getThreadCategory(
                thread: &mutableThread,
                ownTweetIDs: ownTweetIDs,
                archiveUsername: archiveUsername
            )
            return targetJournal(for: category, settings: settings) != nil
        }

        let alreadyProcessed: Set<String>
        let alreadyImportedCount: Int
        let pendingThreads: [[Tweet]]

        if settings.skipAlreadyImported {
            alreadyProcessed = try loadProcessedTweetIDs(statusesFileURL: statusesFileURL)
            alreadyImportedCount = filteredThreads.reduce(into: 0) { partialResult, thread in
                if let id = thread.first?.idStr, alreadyProcessed.contains(id) {
                    partialResult += 1
                }
            }

            pendingThreads = filteredThreads.filter { thread in
                guard let firstID = thread.first?.idStr else { return false }
                return !alreadyProcessed.contains(firstID)
            }
        } else {
            alreadyProcessed = []
            alreadyImportedCount = 0
            pendingThreads = filteredThreads
        }

        let overview = ArchiveOverview(
            archivePath: archive.archiveRootURL.path,
            statusesFilePath: statusesFileURL.path,
            sourcePath: archive.droppedURL.path,
            sourceWasZip: archive.extractedFromZip,
            archiveUsername: archiveUsername,
            archiveDisplayName: accountProfile?.accountDisplayName?.trimmedNilIfEmpty,
            totalTweets: tweets.count,
            threadsBeforeDateFilter: allThreads.count,
            threadsInDateRange: filteredThreads.count,
            alreadyImported: alreadyImportedCount,
            pendingToImport: pendingThreads.count,
            earliestTweetDate: tweets.map(\.createdAt).min(),
            latestTweetDate: tweets.map(\.createdAt).max()
        )

        return PreparedImportContext(
            archive: archive,
            statusesFileURL: statusesFileURL,
            totalTweets: tweets.count,
            filteredThreads: filteredThreads,
            pendingThreads: pendingThreads,
            alreadyProcessedIDs: alreadyProcessed,
            ownTweetIDs: ownTweetIDs,
            overview: overview
        )
    }

    func runImport(
        context: PreparedImportContext,
        settings: ImportSettings,
        progress: @escaping @Sendable (ImportProgressSnapshot) -> Void
    ) async -> ImportRunSummary {
        let dayOne = DayOneCLI()

        if let availabilityError = dayOne.availabilityError() {
            let failure = ImportRunSummary(
                totalThreads: context.filteredThreads.count,
                alreadyImported: context.overview.alreadyImported,
                importedThisRun: 0,
                skippedThisRun: 0,
                failedThisRun: context.pendingThreads.count,
                attemptedThisRun: 0,
                wasCancelled: false,
                statusMessage: availabilityError
            )

            progress(
                ImportProgressSnapshot(
                    totalThreads: context.filteredThreads.count,
                    alreadyImported: context.overview.alreadyImported,
                    importedThisRun: 0,
                    skippedThisRun: 0,
                    failedThisRun: context.pendingThreads.count,
                    currentIndex: 0,
                    currentTweetID: nil,
                    currentCategory: nil,
                    statusMessage: availabilityError
                )
            )
            return failure
        }

        let totalThreads = context.filteredThreads.count
        let alreadyImported = context.overview.alreadyImported

        var imported = 0
        var skipped = 0
        var failed = 0
        var attempted = 0
        var processedIndex = 0
        var llmFallbackReports = 0

        func emitStatus(_ message: String, tweetID: String? = nil, category: String? = nil) {
            progress(
                ImportProgressSnapshot(
                    totalThreads: totalThreads,
                    alreadyImported: alreadyImported,
                    importedThisRun: imported,
                    skippedThisRun: skipped,
                    failedThisRun: failed,
                    currentIndex: processedIndex,
                    currentTweetID: tweetID,
                    currentCategory: category,
                    statusMessage: message
                )
            )
        }

        emitStatus("Starting import")

        if settings.processTitlesWithLLM {
            emitStatus("LLM naming enabled (\(settings.ollamaModelName)).")
        } else {
            emitStatus("LLM naming disabled for this run.")
        }

        for thread in context.pendingThreads {
            if Task.isCancelled {
                return ImportRunSummary(
                    totalThreads: totalThreads,
                    alreadyImported: alreadyImported,
                    importedThisRun: imported,
                    skippedThisRun: skipped,
                    failedThisRun: failed,
                    attemptedThisRun: attempted,
                    wasCancelled: true,
                    statusMessage: "Import cancelled"
                )
            }

            guard !thread.isEmpty else {
                continue
            }

            var mutableThread = thread
            let firstTweet = mutableThread[0]

            attempted += 1
            processedIndex += 1

            let tweetID = firstTweet.idStr
            let category = getThreadCategory(
                thread: &mutableThread,
                ownTweetIDs: context.ownTweetIDs,
                archiveUsername: context.overview.archiveUsername?.trimmedNilIfEmpty
            )
            let archiveUsername = context.overview.archiveUsername?.trimmedNilIfEmpty

            let aggregate = aggregateThreadData(thread: mutableThread, archiveUsername: archiveUsername)
            let titleOutcome = await generateEntryTitle(
                entryText: aggregate.text,
                category: category,
                threadLength: mutableThread.count,
                settings: settings
            )

            if let reason = titleOutcome.failureReason, llmFallbackReports < 12 {
                llmFallbackReports += 1
                emitStatus("LLM naming fallback for \(tweetID): \(reason)", tweetID: tweetID, category: category)
            }

            let entryText = buildEntryContent(
                entryText: aggregate.text,
                firstTweet: firstTweet,
                title: titleOutcome.title
            )

            guard let targetJournal = targetJournal(for: category, settings: settings) else {
                if settings.skipAlreadyImported {
                    do {
                        try saveProcessedTweetID(tweetID, statusesFileURL: context.statusesFileURL)
                    } catch {
                        failed += 1
                        emitStatus(
                            "Failed to persist skipped tweet ID \(tweetID): \(error.localizedDescription)",
                            tweetID: tweetID,
                            category: category
                        )
                        continue
                    }
                }

                skipped += 1
                emitStatus("Skipped \(tweetID) (\(category))", tweetID: tweetID, category: category)
                continue
            }

            let payload = DayOnePayload(
                text: entryText,
                journal: targetJournal,
                tags: Array(Set(aggregate.tags)).sorted(),
                date: aggregate.date,
                coordinate: aggregate.coordinate,
                attachments: aggregate.mediaFiles
            )

            let commandResult = dayOne.addPost(payload: payload)
            if commandResult.success {
                imported += 1
                if settings.skipAlreadyImported {
                    do {
                        try saveProcessedTweetID(tweetID, statusesFileURL: context.statusesFileURL)
                    } catch {
                        failed += 1
                        emitStatus(
                            "Imported \(tweetID), but failed to save status: \(error.localizedDescription)",
                            tweetID: tweetID,
                            category: category
                        )
                        continue
                    }
                }

                let rawOutput = commandResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let statusMessage = rawOutput.isEmpty ? "Imported \(tweetID)" : "Imported \(tweetID): \(rawOutput)"
                emitStatus(statusMessage, tweetID: tweetID, category: category)
            } else {
                failed += 1
                let detail = commandResult.stderr.trimmedNilIfEmpty ?? "Day One command failed with exit code \(commandResult.exitCode)."
                emitStatus("Failed \(tweetID): \(detail)", tweetID: tweetID, category: category)
            }
        }

        let summaryMessage = "Import finished: \(imported) imported, \(skipped) skipped, \(failed) failed"
        return ImportRunSummary(
            totalThreads: totalThreads,
            alreadyImported: alreadyImported,
            importedThisRun: imported,
            skippedThisRun: skipped,
            failedThisRun: failed,
            attemptedThisRun: attempted,
            wasCancelled: false,
            statusMessage: summaryMessage
        )
    }

    private func resolveZipDrop(zipURL: URL) throws -> ArchiveLocation {
        let parentDirectory = zipURL.deletingLastPathComponent()
        let extractionRoot = parentDirectory.appendingPathComponent(
            zipURL.deletingPathExtension().lastPathComponent,
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        } catch {
            throw ImportEngineError.zipExtractionFailed(
                "Unable to create extraction directory '\(extractionRoot.path)': \(error.localizedDescription)"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, extractionRoot.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ImportEngineError.zipExtractionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: errorData, encoding: .utf8) ?? "Unknown extraction error"
            throw ImportEngineError.zipExtractionFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let selectedRoot: URL
        let directTweetsFile = extractionRoot.appendingPathComponent("data/tweets.js")
        if fileManager.fileExists(atPath: directTweetsFile.path) {
            selectedRoot = extractionRoot
        } else {
            let rootsInsideExtraction = candidateArchiveRoots(in: extractionRoot)
            if let newest = newestURL(in: rootsInsideExtraction) {
                selectedRoot = newest
            } else {
                throw ImportEngineError.noTwitterArchiveFound(extractionRoot)
            }
        }

        let tweetsJSURL = selectedRoot.appendingPathComponent("data/tweets.js")
        guard fileManager.fileExists(atPath: tweetsJSURL.path) else {
            throw ImportEngineError.tweetsFileMissing(selectedRoot)
        }

        return ArchiveLocation(
            droppedURL: zipURL,
            archiveRootURL: selectedRoot,
            dataDirectoryURL: selectedRoot.appendingPathComponent("data"),
            tweetsJSURL: tweetsJSURL,
            extractedFromZip: true
        )
    }

    private func resolveDirectoryDrop(directoryURL: URL, sourceWasZip: Bool) throws -> ArchiveLocation {
        let directTweetsFile = directoryURL.appendingPathComponent("data/tweets.js")
        if fileManager.fileExists(atPath: directTweetsFile.path) {
            return ArchiveLocation(
                droppedURL: directoryURL,
                archiveRootURL: directoryURL,
                dataDirectoryURL: directoryURL.appendingPathComponent("data"),
                tweetsJSURL: directTweetsFile,
                extractedFromZip: sourceWasZip
            )
        }

        let candidates = candidateArchiveRoots(in: directoryURL)
        guard !candidates.isEmpty else {
            throw ImportEngineError.noTwitterArchiveFound(directoryURL)
        }

        let selectedRoot = candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last ?? directoryURL
        let tweetsJSURL = selectedRoot.appendingPathComponent("data/tweets.js")
        guard fileManager.fileExists(atPath: tweetsJSURL.path) else {
            throw ImportEngineError.tweetsFileMissing(selectedRoot)
        }

        return ArchiveLocation(
            droppedURL: directoryURL,
            archiveRootURL: selectedRoot,
            dataDirectoryURL: selectedRoot.appendingPathComponent("data"),
            tweetsJSURL: tweetsJSURL,
            extractedFromZip: sourceWasZip
        )
    }

    private func candidateArchiveRoots(in directory: URL) -> [URL] {
        var roots = Set<URL>()
        let baseDepth = directory.pathComponents.count

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let depth = fileURL.pathComponents.count - baseDepth
            if depth > 6 {
                enumerator.skipDescendants()
                continue
            }

            if fileURL.lastPathComponent == "tweets.js",
               fileURL.deletingLastPathComponent().lastPathComponent == "data" {
                roots.insert(fileURL.deletingLastPathComponent().deletingLastPathComponent())
            }
        }

        return Array(roots)
    }

    private func newestURL(in urls: [URL]) -> URL? {
        guard !urls.isEmpty else { return nil }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        return urls.max { lhs, rhs in
            let leftValues = try? lhs.resourceValues(forKeys: keys)
            let rightValues = try? rhs.resourceValues(forKeys: keys)
            let leftDate = leftValues?.contentModificationDate ?? leftValues?.creationDate ?? .distantPast
            let rightDate = rightValues?.contentModificationDate ?? rightValues?.creationDate ?? .distantPast
            return leftDate < rightDate
        }
    }

    private func dateRange(from settings: ImportSettings) -> (start: Date, end: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: settings.startDate)
        let endOfSelectedDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: settings.endDate)) ?? settings.endDate
        return (start: start, end: max(start, endOfSelectedDay))
    }

    private func loadAccountProfile(from accountJSURL: URL) -> AccountProfile? {
        guard fileManager.fileExists(atPath: accountJSURL.path) else {
            return nil
        }

        guard let contents = try? String(contentsOf: accountJSURL, encoding: .utf8) else {
            return nil
        }

        guard let jsonStart = contents.firstIndex(of: "[") else {
            return nil
        }

        let jsonPayload = String(contents[jsonStart...])
        guard let data = jsonPayload.data(using: .utf8) else {
            return nil
        }

        guard let envelopes = try? JSONDecoder().decode([AccountEnvelope].self, from: data) else {
            return nil
        }

        return envelopes.first?.account
    }

    private func loadTweets(from tweetsJSURL: URL) throws -> [Tweet] {
        let contents: String
        do {
            contents = try String(contentsOf: tweetsJSURL, encoding: .utf8)
        } catch {
            throw ImportEngineError.tweetsFileReadFailed(
                path: tweetsJSURL.path,
                details: error.localizedDescription
            )
        }

        guard let jsonStart = contents.firstIndex(of: "[") else {
            throw ImportEngineError.invalidTweetsJSON(
                path: tweetsJSURL.path,
                reason: "No '[' found. Expected a JavaScript header followed by a JSON array.",
                preview: previewText(contents)
            )
        }

        let jsonPayload = String(contents[jsonStart...])
        guard let data = jsonPayload.data(using: .utf8) else {
            throw ImportEngineError.invalidTweetsJSON(
                path: tweetsJSURL.path,
                reason: "Could not convert parsed payload to UTF-8 data.",
                preview: previewText(jsonPayload)
            )
        }

        do {
            let envelopes = try JSONDecoder().decode([TweetEnvelope].self, from: data)
            return envelopes.map(\.tweet)
        } catch let decodingError as DecodingError {
            throw ImportEngineError.cannotDecodeTweets(
                path: tweetsJSURL.path,
                details: describeDecodingError(decodingError),
                preview: previewText(jsonPayload)
            )
        } catch {
            throw ImportEngineError.cannotDecodeTweets(
                path: tweetsJSURL.path,
                details: error.localizedDescription,
                preview: previewText(jsonPayload)
            )
        }
    }

    private func previewText(
        _ text: String,
        maxLength: Int = 260,
        emptyPlaceholder: String = "<empty>"
    ) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return emptyPlaceholder
        }

        if normalized.count <= maxLength {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return "\(normalized[..<endIndex])..."
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Corrupted data at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "<root>"
        }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }

    private func combineThreads(tweets: [Tweet]) -> [[Tweet]] {
        let tweetByID = Dictionary(uniqueKeysWithValues: tweets.map { ($0.idStr, $0) })

        var childrenMap: [String: [Tweet]] = [:]
        var allChildIDs = Set<String>()

        for tweet in tweets {
            guard let parentID = tweet.inReplyToStatusID, tweetByID[parentID] != nil else {
                continue
            }
            childrenMap[parentID, default: []].append(tweet)
            allChildIDs.insert(tweet.idStr)
        }

        let roots = tweets
            .filter { !allChildIDs.contains($0.idStr) }
            .sorted { numericTweetID($0.idStr) < numericTweetID($1.idStr) }

        var finalThreads: [[Tweet]] = []
        var processedIDs = Set<String>()

        for root in roots {
            if processedIDs.contains(root.idStr) {
                continue
            }

            var queue: [Tweet] = [root]
            var queueIndex = 0
            var currentThread: [Tweet] = []

            // Use index-based traversal to avoid O(n^2) cost from repeated removeFirst().
            while queueIndex < queue.count {
                let currentTweet = queue[queueIndex]
                queueIndex += 1

                currentThread.append(currentTweet)
                processedIDs.insert(currentTweet.idStr)

                let children = (childrenMap[currentTweet.idStr] ?? [])
                    .sorted { numericTweetID($0.idStr) < numericTweetID($1.idStr) }
                queue.append(contentsOf: children)
            }

            if !currentThread.isEmpty {
                finalThreads.append(currentThread)
            }
        }

        return finalThreads
    }

    private func processTweetTextForMarkdownLinks(tweet: inout Tweet, archiveDataDirectory: URL) {
        let linksToProcess = tweet.entities.urls.compactMap { urlEntity -> (tco: String, markdown: String)? in
            guard let tco = urlEntity.url, let expanded = urlEntity.expandedURL else {
                return nil
            }
            let linkText = urlEntity.displayURL ?? expanded
            return (tco: tco, markdown: "[\(linkText)](\(expanded))")
        }

        var mediaByTCO: [String: [(url: String, type: String)]] = [:]
        let mediaEntities = (tweet.extendedEntities?.media.isEmpty == false) ? (tweet.extendedEntities?.media ?? []) : tweet.entities.media

        for media in mediaEntities {
            guard let tco = media.url, let type = media.type else { continue }

            if type == "photo", let mediaURL = media.mediaURLHTTPS {
                mediaByTCO[tco, default: []].append((url: mediaURL, type: type))
                continue
            }

            if type == "video" || type == "animated_gif" {
                let mp4Variants = (media.videoInfo?.variants ?? [])
                    .compactMap { variant -> (Int, String)? in
                        guard variant.contentType == "video/mp4",
                              let bitrate = variant.bitrate,
                              let url = variant.url else {
                            return nil
                        }
                        return (bitrate, url)
                    }

                if let best = mp4Variants.max(by: { $0.0 < $1.0 }) {
                    mediaByTCO[tco, default: []].append((url: best.1, type: type))
                }
            }
        }

        var processedText = tweet.fullText
        processedText = processedText.replacingRegex(
            pattern: "https?://t\\.co/[A-Za-z0-9]+(?:\\.\\.\\.|…)",
            with: "[link truncated]"
        )

        for link in linksToProcess.sorted(by: { $0.tco.count > $1.tco.count }) {
            if mediaByTCO[link.tco] != nil {
                continue
            }
            processedText = processedText.replacingOccurrences(of: link.tco, with: link.markdown)
        }

        var mediaFiles: [String] = []
        for tco in mediaByTCO.keys.sorted(by: { $0.count > $1.count }) {
            guard let items = mediaByTCO[tco] else { continue }
            let placeholders = String(repeating: "[{attachment}]", count: items.count)
            processedText = processedText.replacingOccurrences(of: tco, with: placeholders)

            for item in items {
                var mediaFileName = URL(string: item.url)?.lastPathComponent ?? URL(fileURLWithPath: item.url).lastPathComponent
                if let questionMark = mediaFileName.firstIndex(of: "?") {
                    mediaFileName = String(mediaFileName[..<questionMark])
                }

                if item.type == "video" || item.type == "animated_gif" {
                    let stem = URL(fileURLWithPath: mediaFileName).deletingPathExtension().lastPathComponent
                    mediaFileName = "\(stem).mp4"
                }

                let fullPath = archiveDataDirectory
                    .appendingPathComponent("tweets_media")
                    .appendingPathComponent("\(tweet.idStr)-\(mediaFileName)")
                    .path
                mediaFiles.append(fullPath)
            }
        }

        tweet.fullText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        tweet.mediaFiles = mediaFiles
    }

    private func loadProcessedTweetIDs(statusesFileURL: URL) throws -> Set<String> {
        guard fileManager.fileExists(atPath: statusesFileURL.path) else {
            return []
        }

        let contents = try String(contentsOf: statusesFileURL, encoding: .utf8)
        return Set(contents.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func saveProcessedTweetID(_ tweetID: String, statusesFileURL: URL) throws {
        try fileManager.createDirectory(
            at: statusesFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: statusesFileURL.path) {
            fileManager.createFile(atPath: statusesFileURL.path, contents: Data())
        }

        let handle = try FileHandle(forWritingTo: statusesFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = "\(tweetID)\n".data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func aggregateThreadData(
        thread: [Tweet],
        archiveUsername: String?
    ) -> ThreadAggregate {
        guard let firstTweet = thread.first else {
            return ThreadAggregate(text: "", tags: [], mediaFiles: [], date: Date(), coordinate: nil)
        }

        let firstTweetDate = firstTweet.createdAt

        var entryText = ""
        var tags: [String] = []
        var mediaFiles: [String] = []
        var coordinate: (latitude: Double, longitude: Double)?

        for (index, tweet) in thread.enumerated() {
            entryText += tweet.fullText + "\n\n"

            var metrics: [String] = []

            if let username = archiveUsername {
                let tweetURL = "https://twitter.com/\(username)/status/\(tweet.idStr)"
                if tweet.favoriteCount > 0 {
                    metrics.append("[Likes: \(tweet.favoriteCount)](\(tweetURL)/likes)")
                }
                if tweet.retweetCount > 0 {
                    metrics.append("[Retweets: \(tweet.retweetCount)](\(tweetURL)/retweets)")
                }
                metrics.append("[Open on twitter.com](\(tweetURL))")
            } else {
                if tweet.favoriteCount > 0 {
                    metrics.append("Likes: \(tweet.favoriteCount)")
                }
                if tweet.retweetCount > 0 {
                    metrics.append("Retweets: \(tweet.retweetCount)")
                }
            }

            var deltaText = ""
            if index > 0 {
                let seconds = max(0, tweet.createdAt.timeIntervalSince(firstTweetDate))
                if seconds > 600 {
                    deltaText = " (sent \(humanizedDuration(seconds)) later)"
                }
            }

            entryText += metrics.joined(separator: "   ") + deltaText + "\n"
            entryText += "___\n"

            tags.append(contentsOf: tweet.entities.hashtags.map(\.text))
            mediaFiles.append(contentsOf: tweet.mediaFiles)

            if coordinate == nil {
                coordinate = tweet.coordinates?.latitudeLongitude
            }
        }

        return ThreadAggregate(
            text: entryText,
            tags: tags,
            mediaFiles: mediaFiles,
            date: firstTweetDate,
            coordinate: coordinate
        )
    }

    private func humanizedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        return formatter.string(from: seconds) ?? "a while"
    }

    private func generateEntryTitle(
        entryText: String,
        category: String,
        threadLength: Int,
        settings: ImportSettings
    ) async -> TitleGenerationOutcome {
        if category.hasPrefix("Replied to") {
            return TitleGenerationOutcome(title: category, failureReason: nil)
        }

        guard settings.processTitlesWithLLM, threadLength > 1 else {
            return TitleGenerationOutcome(title: category, failureReason: nil)
        }

        let summaryOutcome = await requestLLMSummary(text: entryText, settings: settings)
        guard let summary = summaryOutcome.summary else {
            return TitleGenerationOutcome(
                title: category,
                failureReason: summaryOutcome.failureReason
            )
        }

        return TitleGenerationOutcome(
            title: "Wrote \(summary)",
            failureReason: nil
        )
    }

    private func requestLLMSummary(text: String, settings: ImportSettings) async -> LLMSummaryOutcome {
        guard let url = normalizedOllamaGenerateURL(from: settings.ollamaAPIURL) else {
            print("[Twixodus][Ollama] Invalid URL: \(settings.ollamaAPIURL)")
            return LLMSummaryOutcome(
                summary: nil,
                failureReason: "Invalid Ollama URL: \(settings.ollamaAPIURL)"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "\(settings.ollamaPrompt)\n\nTweet: \(text)\nSummary:"
        let payload: [String: Any] = [
            "model": settings.ollamaModelName,
            "prompt": prompt,
            "stream": false,
            "think": false,
            "options": [
                "num_predict": 48,
                "temperature": 0.2,
                "num_ctx": 8192
            ]
        ]

        do {
            let requestData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = requestData
            let requestPayload = String(data: requestData, encoding: .utf8) ?? "<non-utf8 json payload>"
            print("[Twixodus][Ollama] FULL OLLAMA URL: \(url.absoluteString)")
            print("[Twixodus][Ollama] FULL OLLAMA REQUEST JSON: \(requestPayload)")

            let (responseData, response) = try await URLSession.shared.data(for: request)
            let rawResponse = String(data: responseData, encoding: .utf8) ?? "<non-utf8 response>"
            print("[Twixodus][Ollama] FULL OLLAMA RESPONSE: \(rawResponse)")
            let preview = previewText(rawResponse, maxLength: 240, emptyPlaceholder: "")

            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                return LLMSummaryOutcome(
                    summary: nil,
                    failureReason: "HTTP \(http.statusCode) from \(url.absoluteString). Response: \(preview)"
                )
            }

            guard let parsed = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                return LLMSummaryOutcome(
                    summary: nil,
                    failureReason: "Unexpected non-JSON response from \(url.absoluteString): \(preview)"
                )
            }

            if let summary = (parsed["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                return LLMSummaryOutcome(summary: summary, failureReason: nil)
            }

            if let message = parsed["message"] as? [String: Any],
               let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                return LLMSummaryOutcome(summary: content, failureReason: nil)
            }

            let doneReason = (parsed["done_reason"] as? String) ?? "n/a"
            let model = (parsed["model"] as? String) ?? settings.ollamaModelName
            return LLMSummaryOutcome(
                summary: nil,
                failureReason: "Empty summary from \(url.absoluteString) (model \(model), done_reason \(doneReason)). Raw: \(preview)"
            )
        } catch {
            print("[Twixodus][Ollama] REQUEST FAILED for \(url.absoluteString): \(error.localizedDescription)")
            return LLMSummaryOutcome(
                summary: nil,
                failureReason: "Request to \(url.absoluteString) failed: \(error.localizedDescription)"
            )
        }
    }

    private func buildEntryContent(entryText: String, firstTweet: Tweet, title: String) -> String {
        var output = entryText

        if let replyTargetID = firstTweet.inReplyToStatusID {
            let mentionMatches = output.matches(forRegex: "@\\w+")
            var seen = Set<String>()
            let uniqueMentions = mentionMatches.filter { mention in
                let inserted = seen.insert(mention).inserted
                return inserted
            }

            let rest = output.replacingRegex(pattern: "(?:@\\w+\\s*)+", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mentionsText = uniqueMentions.joined(separator: " ")
            output = "\(rest)\n\nIn response to [this tweet](https://twitter.com/i/web/status/\(replyTargetID)), which is part of the conversation with \(mentionsText)\n"
        }

        let titled = "# \(title)\n\n\(output)\n\n"
        return escapeMarkdown(titled)
    }

    private func escapeMarkdown(_ text: String) -> String {
        var escapedLines: [String] = []

        for (index, originalLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = String(originalLine)
            if line.hasPrefix("# "), index != 0 {
                line = "\\" + line
            } else if let first = line.first, first == "-" || first == "+" || first == ">" {
                line = "\\" + line
            }
            escapedLines.append(line)
        }

        var escaped = escapedLines.joined(separator: "\n")
        for character in ["*", "`", "|", "!"] {
            escaped = escaped.replacingOccurrences(of: character, with: "\\\(character)")
        }

        return escaped
    }

    private func targetJournal(for category: String, settings: ImportSettings) -> String? {
        if category.hasPrefix("Replied to") {
            return settings.normalizedReplyJournalName
        }

        if category.hasPrefix("Retweet") || category.hasPrefix("Retweeted") {
            if settings.ignoreRetweets {
                return nil
            }
        }

        return settings.journalName.trimmedNilIfEmpty ?? "Tweets"
    }

    private func getThreadCategory(
        thread: inout [Tweet],
        ownTweetIDs: Set<String>,
        archiveUsername: String?
    ) -> String {
        guard !thread.isEmpty else {
            return "Empty thread"
        }

        var firstTweet = thread[0]

        let isRetweet = firstTweet.fullText.hasPrefix("RT @") || firstTweet.fullText.hasPrefix("RT \"@")
        let isReply = firstTweet.inReplyToStatusID != nil
        let isCallout = !isReply && (firstTweet.fullText.hasPrefix("@") || firstTweet.fullText.hasPrefix(".@"))

        let mediaTCO: Set<String> = {
            let mediaEntities = (firstTweet.extendedEntities?.media.isEmpty == false) ? (firstTweet.extendedEntities?.media ?? []) : firstTweet.entities.media
            return Set(mediaEntities.compactMap(\.url))
        }()

        let hasNonMediaTwitterLink = firstTweet.entities.urls.contains { urlEntity in
            guard let expanded = urlEntity.expandedURL, let tco = urlEntity.url else { return false }
            let isTwitterURL = expanded.contains("https://twitter.com") || expanded.contains("https://x.com")
            return isTwitterURL && !mediaTCO.contains(tco)
        }

        if isRetweet {
            let name = extractRetweetInPlace(firstTweet: &firstTweet) ?? "@unknown"
            thread[0] = firstTweet
            return "Retweeted \(name)"
        }

        if hasNonMediaTwitterLink && !isReply {
            if let quote = extractQuoteReference(firstTweet: firstTweet),
               isSelfQuote(
                   quote,
                   ownTweetIDs: ownTweetIDs,
                   archiveUsername: archiveUsername
               ) {
                return "Quoted myself"
            }
            let name = extractQuoteHandle(firstTweet: firstTweet) ?? "@unknown"
            return "Quoted \(name)"
        }

        if firstTweet.fullText.contains(" RT @") {
            if let quote = extractQuoteReference(firstTweet: firstTweet),
               isSelfQuote(
                   quote,
                   ownTweetIDs: ownTweetIDs,
                   archiveUsername: archiveUsername
               ) {
                return "Quoted myself"
            }
            let name = extractQuoteHandle(firstTweet: firstTweet) ?? "@unknown"
            return "Quoted \(name)"
        }

        if isReply {
            return replyCategory(firstTweet: firstTweet)
        }

        if isCallout {
            let names = extractCalloutsInPlace(firstTweet: &firstTweet)
            thread[0] = firstTweet
            return "Callout to \(names)"
        }

        if thread.count > 1 {
            return "Wrote a thread"
        }

        return "Tweeted"
    }

    private func replyCategory(firstTweet: Tweet) -> String {
        guard firstTweet.inReplyToStatusID != nil else {
            return "Not a reply"
        }

        let nameMap = caseInsensitiveNameMap(tweet: firstTweet)
        var handlesInOrder: [String] = []
        var seen = Set<String>()

        for handle in firstTweet.fullText.captureGroups(forRegex: "@([A-Za-z0-9_]+)") {
            if seen.insert(handle).inserted {
                handlesInOrder.append(handle)
            }
        }

        if handlesInOrder.isEmpty, let fallback = firstTweet.inReplyToScreenName {
            handlesInOrder = [fallback]
        }

        if handlesInOrder.isEmpty {
            return "Not a reply"
        }

        let displayNames = handlesInOrder.map { handle in
            nameMap[handle.lowercased()] ?? "@\(handle)"
        }

        return "Replied to \(joinNaturalLanguage(displayNames))"
    }

    private func extractRetweetInPlace(firstTweet: inout Tweet) -> String? {
        let regex = try? NSRegularExpression(pattern: "\\bRT\\s+\\\"?@([A-Za-z0-9_]+)\\\"?:\\s*(.*)", options: [.dotMatchesLineSeparators])
        guard let regex else { return nil }

        let text = firstTweet.fullText
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange),
              let handleRange = Range(match.range(at: 1), in: text),
              let remainderRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }

        let handle = String(text[handleRange])
        firstTweet.fullText = String(text[remainderRange])

        let nameMap = caseInsensitiveNameMap(tweet: firstTweet)
        return nameMap[handle.lowercased()] ?? "@\(handle)"
    }

    private func extractCalloutsInPlace(firstTweet: inout Tweet) -> String {
        let regex = try? NSRegularExpression(pattern: "^\\s*[\\\"]?\\.?@([A-Za-z0-9_]+)[\\\"]?\\s*")
        guard let regex else {
            return ""
        }

        var text = firstTweet.fullText
        var handles: [String] = []

        while true {
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: fullRange),
                  match.range.location == 0,
                  let handleRange = Range(match.range(at: 1), in: text),
                  let matchedRange = Range(match.range, in: text)
            else {
                break
            }

            handles.append(String(text[handleRange]))
            text.removeSubrange(matchedRange)
        }

        if !handles.isEmpty {
            firstTweet.fullText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let nameMap = caseInsensitiveNameMap(tweet: firstTweet)
        let displayNames = handles.map { handle in
            nameMap[handle.lowercased()] ?? "@\(handle)"
        }

        return joinNaturalLanguage(displayNames)
    }

    private func extractQuoteHandle(firstTweet: Tweet) -> String? {
        extractQuoteReference(firstTweet: firstTweet).map { "@\($0.handle)" }
    }

    private func extractQuoteReference(firstTweet: Tweet) -> QuoteReference? {
        for urlEntity in firstTweet.entities.urls {
            guard let expanded = urlEntity.expandedURL else { continue }
            if let reference = quoteReference(from: expanded) {
                return reference
            }
        }
        return nil
    }

    private func isSelfQuote(
        _ quote: QuoteReference,
        ownTweetIDs: Set<String>,
        archiveUsername: String?
    ) -> Bool {
        // Status IDs in the user's archive are canonical and remain stable across handle changes.
        if ownTweetIDs.contains(quote.statusID) {
            return true
        }

        let normalizedHandle = quote.handle.lowercased()
        if let archiveUsername, archiveUsername.lowercased() == normalizedHandle {
            return true
        }

        return false
    }

    private func quoteReference(from url: String) -> QuoteReference? {
        let fullRange = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = Self.quoteURLRegex.firstMatch(in: url, range: fullRange),
              let handleRange = Range(match.range(at: 1), in: url),
              let statusRange = Range(match.range(at: 2), in: url)
        else {
            return nil
        }

        return QuoteReference(
            handle: String(url[handleRange]),
            statusID: String(url[statusRange])
        )
    }

    private static let quoteURLRegex: NSRegularExpression = {
        let pattern = "https?://(?:www\\.)?(?:twitter\\.com|x\\.com)/([^/]+)/status/(\\d+)"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private func caseInsensitiveNameMap(tweet: Tweet) -> [String: String] {
        // Archives can repeat the same mention handle multiple times in one tweet.
        // Build the map defensively instead of trapping on duplicate keys.
        tweet.entities.userMentions.reduce(into: [:]) { result, mention in
            let key = mention.screenName.lowercased()
            let value = mention.name ?? "@\(mention.screenName)"
            if result[key] == nil {
                result[key] = value
            }
        }
    }

    private func joinNaturalLanguage(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            return "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }

    private func numericTweetID(_ id: String) -> Int64 {
        Int64(id) ?? 0
    }
}
