import Foundation

struct ArchiveLocation: Sendable, Equatable {
    let droppedURL: URL
    let archiveRootURL: URL
    let dataDirectoryURL: URL
    let tweetsJSURL: URL
    let extractedFromZip: Bool

    var displayName: String {
        archiveRootURL.lastPathComponent
    }
}

struct ArchiveOverview: Sendable {
    let archivePath: String
    let statusesFilePath: String
    let sourcePath: String
    let sourceWasZip: Bool
    let archiveUsername: String?
    let archiveDisplayName: String?
    let totalTweets: Int
    let threadsBeforeDateFilter: Int
    let threadsInDateRange: Int
    let alreadyImported: Int
    let pendingToImport: Int
    let earliestTweetDate: Date?
    let latestTweetDate: Date?
}

struct PreparedImportContext: Sendable {
    let archive: ArchiveLocation
    let statusesFileURL: URL
    let totalTweets: Int
    let filteredThreads: [[Tweet]]
    let pendingThreads: [[Tweet]]
    let alreadyProcessedIDs: Set<String>
    let overview: ArchiveOverview
}

struct ImportProgressSnapshot: Sendable {
    let totalThreads: Int
    let alreadyImported: Int
    let importedThisRun: Int
    let skippedThisRun: Int
    let failedThisRun: Int
    let currentIndex: Int
    let currentTweetID: String?
    let currentCategory: String?
    let statusMessage: String

    var completedTotal: Int {
        min(totalThreads, alreadyImported + currentIndex)
    }

    var fraction: Double {
        guard totalThreads > 0 else { return 0 }
        return Double(completedTotal) / Double(totalThreads)
    }
}

struct ImportRunSummary: Sendable {
    let totalThreads: Int
    let alreadyImported: Int
    let importedThisRun: Int
    let skippedThisRun: Int
    let failedThisRun: Int
    let attemptedThisRun: Int
    let wasCancelled: Bool
    let statusMessage: String
}

enum ImportEngineError: LocalizedError {
    case droppedItemIsNotFileSystemURL
    case unsupportedDropType
    case zipExtractionFailed(String)
    case noTwitterArchiveFound(URL)
    case tweetsFileMissing(URL)
    case tweetsFileReadFailed(path: String, details: String)
    case invalidTweetsJSON(path: String, reason: String, preview: String)
    case cannotDecodeTweets(path: String, details: String, preview: String)

    var errorDescription: String? {
        switch self {
        case .droppedItemIsNotFileSystemURL:
            return "Dropped item is not a valid local file URL."
        case .unsupportedDropType:
            return "Drop a folder or a .zip archive."
        case .zipExtractionFailed(let details):
            return "Failed to extract zip archive: \(details)"
        case .noTwitterArchiveFound(let directory):
            return "Could not find a Twitter archive under \(directory.path)."
        case .tweetsFileMissing(let archiveRoot):
            return "Could not find data/tweets.js under \(archiveRoot.path)."
        case let .tweetsFileReadFailed(path, details):
            return "Unable to read tweets.js at \(path): \(details)"
        case let .invalidTweetsJSON(path, reason, preview):
            return """
            tweets.js is not in the expected format.
            Path: \(path)
            Reason: \(reason)
            Preview: \(preview)
            """
        case let .cannotDecodeTweets(path, details, preview):
            return """
            Unable to decode tweets.js JSON payload.
            Path: \(path)
            Details: \(details)
            Preview: \(preview)
            """
        }
    }
}

struct TweetEnvelope: Decodable, Sendable {
    var tweet: Tweet
}

struct AccountEnvelope: Decodable, Sendable {
    var account: AccountProfile
}

struct AccountProfile: Decodable, Sendable {
    var username: String?
    var accountDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case username
        case accountDisplayName
    }
}

struct Tweet: Decodable, Sendable {
    var idStr: String
    var fullText: String
    var createdAt: Date
    var favoriteCount: Int
    var retweetCount: Int
    var inReplyToStatusID: String?
    var inReplyToScreenName: String?
    var entities: Entities
    var extendedEntities: ExtendedEntities?
    var coordinates: Coordinates?
    var mediaFiles: [String] = []

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case fullText = "full_text"
        case createdAt = "created_at"
        case favoriteCount = "favorite_count"
        case retweetCount = "retweet_count"
        case inReplyToStatusID = "in_reply_to_status_id_str"
        case inReplyToScreenName = "in_reply_to_screen_name"
        case entities
        case extendedEntities = "extended_entities"
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idStr = try container.decode(String.self, forKey: .idStr)
        fullText = try container.decode(String.self, forKey: .fullText)

        let createdAtRaw = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = Self.createdAtFormatter.date(from: createdAtRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Unexpected date format: \(createdAtRaw)"
            )
        }
        createdAt = parsedDate

        favoriteCount = Self.decodeInt(container: container, key: .favoriteCount) ?? 0
        retweetCount = Self.decodeInt(container: container, key: .retweetCount) ?? 0
        inReplyToStatusID = try container.decodeIfPresent(String.self, forKey: .inReplyToStatusID)
        inReplyToScreenName = try container.decodeIfPresent(String.self, forKey: .inReplyToScreenName)
        entities = try container.decodeIfPresent(Entities.self, forKey: .entities) ?? Entities()
        extendedEntities = try container.decodeIfPresent(ExtendedEntities.self, forKey: .extendedEntities)
        coordinates = try container.decodeIfPresent(Coordinates.self, forKey: .coordinates)
    }

    private static func decodeInt(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return Int(stringValue)
        }
        return nil
    }

    private static let createdAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter
    }()
}

struct Entities: Decodable, Sendable {
    var hashtags: [Hashtag]
    var urls: [URLEntity]
    var media: [MediaEntity]
    var userMentions: [UserMention]

    enum CodingKeys: String, CodingKey {
        case hashtags
        case urls
        case media
        case userMentions = "user_mentions"
    }

    init() {
        hashtags = []
        urls = []
        media = []
        userMentions = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hashtags = try container.decodeIfPresent([Hashtag].self, forKey: .hashtags) ?? []
        urls = try container.decodeIfPresent([URLEntity].self, forKey: .urls) ?? []
        media = try container.decodeIfPresent([MediaEntity].self, forKey: .media) ?? []
        userMentions = try container.decodeIfPresent([UserMention].self, forKey: .userMentions) ?? []
    }
}

struct Hashtag: Decodable, Sendable {
    var text: String
}

struct URLEntity: Decodable, Sendable {
    var url: String?
    var expandedURL: String?
    var displayURL: String?

    enum CodingKeys: String, CodingKey {
        case url
        case expandedURL = "expanded_url"
        case displayURL = "display_url"
    }
}

struct UserMention: Decodable, Sendable {
    var screenName: String
    var name: String?

    enum CodingKeys: String, CodingKey {
        case screenName = "screen_name"
        case name
    }
}

struct ExtendedEntities: Decodable, Sendable {
    var media: [MediaEntity]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        media = try container.decodeIfPresent([MediaEntity].self, forKey: .media) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case media
    }
}

struct MediaEntity: Decodable, Sendable {
    var url: String?
    var type: String?
    var mediaURLHTTPS: String?
    var videoInfo: VideoInfo?

    enum CodingKeys: String, CodingKey {
        case url
        case type
        case mediaURLHTTPS = "media_url_https"
        case videoInfo = "video_info"
    }
}

struct VideoInfo: Decodable, Sendable {
    var variants: [VideoVariant]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variants = try container.decodeIfPresent([VideoVariant].self, forKey: .variants) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case variants
    }
}

struct VideoVariant: Decodable, Sendable {
    var bitrate: Int?
    var contentType: String?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case bitrate
        case contentType = "content_type"
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intValue = try? container.decode(Int.self, forKey: .bitrate) {
            bitrate = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .bitrate), let intValue = Int(stringValue) {
            bitrate = intValue
        } else {
            bitrate = nil
        }
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}

struct Coordinates: Decodable, Sendable {
    var coordinates: [Double]

    enum CodingKeys: String, CodingKey {
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([LossyDouble].self, forKey: .coordinates)
        coordinates = values.map(\.value)
    }

    var latitudeLongitude: (latitude: Double, longitude: Double)? {
        guard coordinates.count >= 2 else {
            return nil
        }
        return (latitude: coordinates[1], longitude: coordinates[0])
    }
}

private struct LossyDouble: Decodable, Sendable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
            return
        }
        if let string = try? container.decode(String.self), let double = Double(string) {
            value = double
            return
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a number or numeric string for coordinate."
            )
        )
    }
}

struct DayOnePayload: Sendable {
    let text: String
    let journal: String?
    let tags: [String]
    let date: Date?
    let coordinate: (latitude: Double, longitude: Double)?
    let attachments: [String]
}

struct DayOneCommandResult: Sendable {
    let success: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct ThreadAggregate: Sendable {
    let text: String
    let tags: [String]
    let mediaFiles: [String]
    let date: Date
    let coordinate: (latitude: Double, longitude: Double)?
}

final class DayOneCLI {
    private let fileManager = FileManager.default

    func availabilityError() -> String? {
        resolveExecutablePath() == nil ? "Could not find Day One CLI executable ('dayone')." : nil
    }

    func installedExecutablePath() -> String? {
        resolveExecutablePath()
    }

    func listJournals() -> (journals: [String]?, error: String?) {
        guard let executablePath = resolveExecutablePath() else {
            return (nil, "Day One CLI is not installed.")
        }

        let result = runCommand(executablePath: executablePath, arguments: ["journals"])
        guard result.success else {
            let detail = result.stderr.trimmedNilIfEmpty ?? "Day One CLI failed to list journals."
            return (nil, detail)
        }

        let lines = result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (lines, nil)
    }

    func addPost(payload: DayOnePayload) -> DayOneCommandResult {
        guard let executablePath = resolveExecutablePath() else {
            return DayOneCommandResult(
                success: false,
                stdout: "",
                stderr: "Could not find Day One CLI executable ('dayone').",
                exitCode: -1
            )
        }

        var arguments = ["new", payload.text]

        if let journal = payload.journal?.trimmedNilIfEmpty {
            arguments += ["--journal", journal]
        }

        if !payload.tags.isEmpty {
            arguments.append("--tags")
            arguments.append(contentsOf: payload.tags)
        }

        if let date = payload.date {
            arguments += ["--date", Self.utcOutputFormatter.string(from: date), "-z", "UTC"]
        }

        if let coordinate = payload.coordinate {
            arguments += ["--coordinate", String(coordinate.latitude), String(coordinate.longitude)]
        }

        if !payload.attachments.isEmpty {
            arguments.append("--attachments")
            arguments.append(contentsOf: payload.attachments)
        }

        let initial = runCommand(executablePath: executablePath, arguments: arguments)
        if initial.success || payload.attachments.isEmpty {
            return initial
        }

        if let attachmentIndex = arguments.firstIndex(of: "--attachments") {
            let retryArguments = Array(arguments[..<attachmentIndex])
            return runCommand(executablePath: executablePath, arguments: retryArguments)
        }

        return initial
    }

    private func runCommand(executablePath: String, arguments: [String]) -> DayOneCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return DayOneCommandResult(
                success: process.terminationStatus == 0,
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            )
        } catch {
            return DayOneCommandResult(
                success: false,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: -1
            )
        }
    }

    private func resolveExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/dayone",
            "/usr/local/bin/dayone",
            "/usr/bin/dayone",
            "/opt/homebrew/bin/dayone2",
            "/usr/local/bin/dayone2",
            "/usr/bin/dayone2"
        ]

        if let existing = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return existing
        }

        if let discovered = which("dayone") {
            return discovered
        }

        if let discovered = which("dayone2") {
            return discovered
        }

        return nil
    }

    private func which(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, !output.isEmpty else { return nil }
            return output
        } catch {
            return nil
        }
    }

    private static let utcOutputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

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

        let allThreads = combineThreads(tweets: tweets)
        let range = dateRange(from: settings)

        let filteredThreads = allThreads
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
            archiveUsername: accountProfile?.username?.trimmedNilIfEmpty,
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

        progress(
            ImportProgressSnapshot(
                totalThreads: totalThreads,
                alreadyImported: alreadyImported,
                importedThisRun: imported,
                skippedThisRun: skipped,
                failedThisRun: failed,
                currentIndex: processedIndex,
                currentTweetID: nil,
                currentCategory: nil,
                statusMessage: "Starting import"
            )
        )

        if settings.processTitlesWithLLM {
            progress(
                ImportProgressSnapshot(
                    totalThreads: totalThreads,
                    alreadyImported: alreadyImported,
                    importedThisRun: imported,
                    skippedThisRun: skipped,
                    failedThisRun: failed,
                    currentIndex: processedIndex,
                    currentTweetID: nil,
                    currentCategory: nil,
                    statusMessage: "LLM naming enabled (\(settings.ollamaModelName))."
                )
            )
        } else {
            progress(
                ImportProgressSnapshot(
                    totalThreads: totalThreads,
                    alreadyImported: alreadyImported,
                    importedThisRun: imported,
                    skippedThisRun: skipped,
                    failedThisRun: failed,
                    currentIndex: processedIndex,
                    currentTweetID: nil,
                    currentCategory: nil,
                    statusMessage: "LLM naming disabled for this run."
                )
            )
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
            let category = getThreadCategory(thread: &mutableThread)
            let archiveUsername = context.overview.archiveUsername?.trimmedNilIfEmpty

            let aggregate = aggregateThreadData(
                thread: mutableThread,
                archiveUsername: archiveUsername
            )
            let titleOutcome = await generateEntryTitle(
                entryText: aggregate.text,
                category: category,
                threadLength: mutableThread.count,
                settings: settings
            )

            if let reason = titleOutcome.failureReason, llmFallbackReports < 12 {
                llmFallbackReports += 1
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
                        statusMessage: "LLM naming fallback for \(tweetID): \(reason)"
                    )
                )
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
                                statusMessage: "Failed to persist skipped tweet ID \(tweetID): \(error.localizedDescription)"
                            )
                        )
                        continue
                    }
                }

                skipped += 1
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
                        statusMessage: "Skipped \(tweetID) (\(category))"
                    )
                )
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
                                statusMessage: "Imported \(tweetID), but failed to save status: \(error.localizedDescription)"
                            )
                        )
                        continue
                    }
                }

                let rawOutput = commandResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let statusMessage = rawOutput.isEmpty ? "Imported \(tweetID)" : "Imported \(tweetID): \(rawOutput)"
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
                        statusMessage: statusMessage
                    )
                )
            } else {
                failed += 1
                let detail = commandResult.stderr.trimmedNilIfEmpty ?? "Day One command failed with exit code \(commandResult.exitCode)."
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
                        statusMessage: "Failed \(tweetID): \(detail)"
                    )
                )
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

    private func previewText(_ text: String, maxLength: Int = 260) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "<empty>"
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
            var currentThread: [Tweet] = []

            while let currentTweet = queue.first {
                queue.removeFirst()
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
            let preview = previewText(rawResponse, limit: 240)

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

    private func previewText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > limit else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<endIndex])..."
    }

    private func normalizedOllamaGenerateURL(from raw: String) -> URL? {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        guard components.scheme != nil, components.host != nil else {
            return nil
        }

        let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || path == "/" || path == "/api" {
            components.path = "/api/generate"
        }

        return components.url
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

    private func getThreadCategory(thread: inout [Tweet]) -> String {
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
            let name = extractQuoteHandle(firstTweet: firstTweet) ?? "@unknown"
            return "Quoted \(name)"
        }

        if firstTweet.fullText.contains(" RT @") {
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
        for urlEntity in firstTweet.entities.urls {
            guard let expanded = urlEntity.expandedURL else { continue }
            let handles = expanded.captureGroups(forRegex: "https?://(?:www\\.)?(?:twitter\\.com|x\\.com)/([^/]+)/status/\\d+")
            if let first = handles.first {
                return "@\(first)"
            }
        }
        return nil
    }

    private func caseInsensitiveNameMap(tweet: Tweet) -> [String: String] {
        Dictionary(uniqueKeysWithValues: tweet.entities.userMentions.map { mention in
            (mention.screenName.lowercased(), mention.name ?? "@\(mention.screenName)")
        })
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

actor ImportCoordinator {
    func resolveAndPrepare(dropURL: URL, settings: ImportSettings) throws -> PreparedImportContext {
        let engine = TwitterImportEngine()
        let archive = try engine.resolveDrop(url: dropURL)
        return try engine.prepareImportContext(archive: archive, settings: settings)
    }

    func refresh(archive: ArchiveLocation, settings: ImportSettings) throws -> PreparedImportContext {
        let engine = TwitterImportEngine()
        return try engine.prepareImportContext(archive: archive, settings: settings)
    }

    func runImport(
        context: PreparedImportContext,
        settings: ImportSettings,
        progress: @escaping @Sendable (ImportProgressSnapshot) -> Void
    ) async -> ImportRunSummary {
        let engine = TwitterImportEngine()
        return await engine.runImport(context: context, settings: settings, progress: progress)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func replacingRegex(pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }

    func matches(forRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: self) else { return nil }
            return String(self[matchRange])
        }
    }

    func captureGroups(forRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return String(self[matchRange])
        }
    }
}
