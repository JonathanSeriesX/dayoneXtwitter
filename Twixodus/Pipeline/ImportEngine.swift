// Steps 4–7 of the pipeline: select the threads for the date range, import
// them one entry at a time, and produce the delete-the-duplicates report.
// This is main.py's loop, reshaped for a GUI: it reports progress through
// callbacks and supports pausing and cancelling between entries.

import Foundation

/// Thread-safe pause/cancel flags shared between the UI and the import loop.
public final class ImportControl {
    private let lock = NSLock()
    private var paused = false

    public init() {}

    public var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    public func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }
}

public enum ImportLogKind {
    case info
    case thread  // a tweet-by-tweet preview of the thread being imported
    case success
    case warning
    case error
}

public struct ImportCallbacks {
    public var log: (String, ImportLogKind) -> Void
    /// (imported so far, total pending in this run)
    public var progress: (Int, Int) -> Void
    /// A one-line description of what the engine is doing right now.
    public var activity: (String) -> Void

    public init(
        log: @escaping (String, ImportLogKind) -> Void = { _, _ in },
        progress: @escaping (Int, Int) -> Void = { _, _ in },
        activity: @escaping (String) -> Void = { _ in }
    ) {
        self.log = log
        self.progress = progress
        self.activity = activity
    }
}

public struct ImportRunResult {
    public var importedCount = 0
    public var skippedAlreadyImported = 0
    public var totalPending = 0
    public var wasCancelled = false
    public var stoppedAtLimit = false
    /// The delete-the-duplicates reminder, when threads were re-imported.
    public var reimportReport: String?
}

public final class ImportEngine {

    private let config: ImportConfig
    private let context: ThreadCategorizer.Context
    private let ledger: ImportLedger
    private let dayOne: DayOneCLI
    private let ollama: OllamaClient?
    private let control: ImportControl
    private let callbacks: ImportCallbacks

    /// Categorization mutates tweet text in place (RT prefixes are stripped),
    /// so a thread must be categorized at most once per loaded archive — even
    /// across several runs in the same app session. The cache keeps the result
    /// keyed by root tweet ID.
    private let categoryCache: CategoryCache

    public final class CategoryCache {
        var categories: [String: String] = [:]
        public init() {}
    }

    public init(
        config: ImportConfig,
        context: ThreadCategorizer.Context,
        ledger: ImportLedger,
        dayOne: DayOneCLI,
        ollama: OllamaClient?,
        categoryCache: CategoryCache,
        control: ImportControl,
        callbacks: ImportCallbacks
    ) {
        self.config = config
        self.context = context
        self.ledger = ledger
        self.dayOne = dayOne
        self.ollama = ollama
        self.categoryCache = categoryCache
        self.control = control
        self.callbacks = callbacks
    }

    // MARK: - The run loop (main.py steps 4–7)

    public func run(threads allThreads: [TweetThread]) async -> ImportRunResult {
        var result = ImportRunResult()
        var threads = allThreads

        // ---- Step 4: pick which threads to import, and in what order ------
        if config.shuffleMode {
            threads.shuffle()
        }

        var processedIDs = ledger.loadProcessedIDs()
        log("Loaded \(processedIDs.count) previously processed tweet IDs.")

        // Threads that started inside the range are imported normally; older
        // threads that were extended within it need a full re-import.
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            threads, startDate: config.startDate, endDate: config.endDate
        )
        if threads.count != inRange.count {
            log("Filtered down to \(inRange.count) threads within the specified date range.")
        }
        if !extended.isEmpty {
            log("\(extended.count) older thread(s) were extended within this date range "
                + "and will be re-imported in full.")
        }

        // Re-imports go first so a max-threads limit can't starve them.
        let plan = extended.map { PlannedImport(thread: $0, isReimport: true) }
            + inRange.map { PlannedImport(thread: $0, isReimport: false) }

        // ---- Steps 5 & 6: import the planned threads, one entry each ------
        result.totalPending = countPendingImports(plan, processedIDs: processedIDs)
        callbacks.progress(0, result.totalPending)

        var reimported: [ImportedEntry] = []

        for (i, planned) in plan.enumerated() {
            if Task.isCancelled {
                result.wasCancelled = true
                break
            }
            await waitWhilePaused()
            if Task.isCancelled {
                result.wasCancelled = true
                break
            }

            if let limit = config.maxThreadsToProcess, i >= limit {
                log("Stopping after processing \(limit) threads.")
                result.stoppedAtLimit = true
                break
            }

            if var entry = await importSingleThread(
                planned.thread, processedIDs: &processedIDs, forceReimport: planned.isReimport,
                skippedCounter: &result.skippedAlreadyImported
            ) {
                result.importedCount += 1
                callbacks.progress(result.importedCount, result.totalPending)
                if planned.isReimport {
                    entry.previousTweetCount = ThreadSelection.countTweetsBefore(
                        planned.thread, startDate: config.startDate)
                    reimported.append(entry)
                }
            }
        }

        // ---- Step 7: remind the user to delete re-imported duplicates -----
        if !reimported.isEmpty {
            result.reimportReport = ThreadSelection.formatReimportReport(
                reimported, startDate: config.startDate, username: config.currentUsername
            )
        }

        return result
    }

    /// How many planned threads this run still has to import: a re-imported
    /// thread is pending until its extension marker is in the ledger, an
    /// ordinary one until its root tweet ID is.
    func countPendingImports(_ plan: [PlannedImport], processedIDs: Set<String>) -> Int {
        plan.filter { planned in
            let key = planned.isReimport
                ? ImportLedger.extensionMarker(planned.thread)
                : planned.thread[0].idStr
            return !processedIDs.contains(key)
        }.count
    }

    // MARK: - One thread → one entry (importer.py)

    /// Imports one thread into Day One, unless the ledger says it's done.
    ///
    /// With forceReimport, the thread is imported even if it was imported
    /// before — used for threads that grew since their last import. Returns an
    /// ImportedEntry describing the created entry, or nil if nothing was posted.
    private func importSingleThread(
        _ thread: TweetThread,
        processedIDs: inout Set<String>,
        forceReimport: Bool,
        skippedCounter: inout Int
    ) async -> ImportedEntry? {
        let firstTweet = thread[0]
        let tweetId = firstTweet.idStr

        if processedIDs.contains(tweetId), !forceReimport {
            skippedCounter += 1
            return nil
        }

        // A re-imported thread is tracked by "<root id>+<last tweet id>", so
        // running the same date range twice doesn't import the same extension
        // over and over.
        let reimportMarker = forceReimport ? ImportLedger.extensionMarker(thread) : nil
        if let marker = reimportMarker {
            if processedIDs.contains(marker) {
                log("Skipping thread \(tweetId): its extension was already imported.")
                skippedCounter += 1
                return nil
            }
            log("Re-importing thread \(tweetId): it was extended within the date range.")
        }

        // Step 5a: name the thread — this also strips RT prefixes from the
        // text, which is why the result is cached (see CategoryCache).
        let category: String
        if let cached = categoryCache.categories[tweetId] {
            category = cached
        } else {
            category = ThreadCategorizer.threadCategory(thread, context: context)
            categoryCache.categories[tweetId] = category
        }
        logThreadPreview(thread, category: category)

        // Step 5b: compose the entry.
        let content = EntryComposer.aggregateThreadData(thread, config: config)
        if config.processTitlesWithLLM {
            callbacks.activity("Titling: \(String(firstTweet.fullText.prefix(80)))")
        }
        let title = await EntryComposer.generateEntryTitle(
            entryText: content.text,
            category: category,
            threadLength: thread.count,
            mediaFiles: content.mediaFiles,
            config: config
        ) { [ollama] text, media in
            guard let ollama else { return nil }
            let generated = await ollama.generateTitle(entryText: text, mediaFiles: media)
            if let generated {
                self.log("Title: \(generated)")
            }
            return generated
        }
        let entryText = EntryComposer.buildEntryContent(
            entryText: content.text, firstTweet: firstTweet, category: category,
            title: title, config: config
        )

        guard let targetJournal = EntryComposer.targetJournal(
            category: category, tweetId: tweetId, config: config,
            log: { self.log($0) }
        ) else {
            // Mark as processed even if skipped
            ledger.rememberProcessed(
                tweetId: tweetId, reimportMarker: reimportMarker, processedIDs: &processedIDs)
            return nil
        }

        // Step 6: hand the entry to the Day One CLI.
        callbacks.activity("Saving to “\(targetJournal)”: \(title)")
        let posted = dayOne.addPost(
            text: entryText,
            journal: targetJournal,
            tags: Array(Set(content.tags)),
            date: content.date,
            coordinate: content.coordinate,
            attachments: content.mediaFiles
        )
        guard posted else { return nil }

        ledger.rememberProcessed(
            tweetId: tweetId, reimportMarker: reimportMarker, processedIDs: &processedIDs)
        return ImportedEntry(
            tweetId: tweetId,
            title: title,
            category: category,
            journal: targetJournal,
            date: content.date ?? firstTweet.createdAt,
            tweetCount: thread.count
        )
    }

    /// Logs the thread being imported, tweet by tweet.
    private func logThreadPreview(_ thread: TweetThread, category: String) {
        let header = thread.count > 1
            ? "— \(category) (\(thread.count) tweets)"
            : "— \(category)"
        callbacks.log(header, .thread)

        for (j, tweet) in thread.enumerated() {
            let indent = j > 0 ? "    " : "  "
            callbacks.log("\(indent)\(tweet.fullText)", .thread)
        }
    }

    // MARK: - Pause / cancel plumbing

    private func waitWhilePaused() async {
        guard control.isPaused else { return }
        callbacks.activity("Paused")
        while control.isPaused && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func log(_ message: String, _ kind: ImportLogKind = .info) {
        callbacks.log(message, kind)
    }
}
