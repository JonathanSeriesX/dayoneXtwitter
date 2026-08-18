// Steps 4–7 of the pipeline: select the threads for the date range, import
// them one entry at a time, and produce the delete-the-duplicates report.
// This is main.py's loop, reshaped for a GUI: it reports progress through
// callbacks and supports pausing and cancelling between entries.

import Foundation

/// Thread-safe pause/cancel flags shared between the UI and the import loop.
///
/// Cancellation lives here, not in Swift's task tree: the app runs the engine
/// on a detached task (to get off the main actor), and detached tasks don't
/// inherit cancellation from the task that awaits them.
public final class ImportControl {
    private let lock = NSLock()
    private var paused = false
    private var cancelled = false

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

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Clears both flags — called once at the start of every run.
    public func reset() {
        lock.lock()
        paused = false
        cancelled = false
        lock.unlock()
    }
}

public enum ImportLogKind {
    case info
    case thread  // the title line that opens each entry's log block
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
    /// Threads that Day One rejected (CLI failed). They are not recorded in
    /// the ledger, so the next run retries them.
    public var failedCount = 0
    /// Threads skipped by configuration: replies with no reply journal set,
    /// retweets when retweets are ignored. Recorded in the ledger as done.
    public var skippedNoJournal = 0
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
    private let dayOne: EntryPosting
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
        dayOne: EntryPosting,
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
        // Debug mode: only the listed threads, imported every time — the
        // ledger is neither consulted nor written (main.py's tweets_to_debug).
        let debugMode = !config.debugTweetIDs.isEmpty
        if debugMode {
            threads = ThreadSelection.filterToDebugIDs(threads, ids: config.debugTweetIDs)
            log("Debug mode: \(threads.count) thread(s) match the listed tweet IDs.")
        }

        switch config.importOrder {
        case .oldestFirst:
            threads = threads.stableSorted { $0[0].createdAt < $1[0].createdAt }
        case .newestFirst:
            threads = threads.stableSorted { $0[0].createdAt > $1[0].createdAt }
        case .random:
            threads.shuffle()
        }

        var processedIDs = debugMode ? Set<String>() : ledger.loadProcessedIDs()
        if !debugMode {
            log("Loaded \(processedIDs.count) previously processed tweet IDs.")
        }

        // Threads that started inside the range are imported normally; older
        // threads that were extended within it need a full re-import.
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            threads, startDate: config.startDate, endDate: config.endDate,
            processedIDs: processedIDs, coveredThrough: config.lastCoveredThrough
        )
        if threads.count != inRange.count {
            log("Filtered down to \(inRange.count) threads within the specified date range.")
        }
        if !extended.isEmpty {
            log("\(extended.count) previously imported thread(s) gained new tweets "
                + "and will be re-imported in full.")
        }

        // Re-imports go first so a max-threads limit can't starve them.
        let plan = extended.map { PlannedImport(thread: $0, isReimport: true) }
            + inRange.map { PlannedImport(thread: $0, isReimport: false) }

        // ---- Steps 5 & 6: import the planned threads, one entry each ------
        result.totalPending = countPendingImports(plan, processedIDs: processedIDs)
        // The denominator for the progress bar. It shrinks when a pending
        // thread turns out not to produce an entry (no target journal, or Day
        // One rejected it), so the bar can actually reach 100%.
        var progressTotal = result.totalPending
        callbacks.progress(0, progressTotal)

        var reimported: [ImportedEntry] = []

        for (i, planned) in plan.enumerated() {
            if cancelRequested {
                result.wasCancelled = true
                break
            }
            await waitWhilePaused()
            if cancelRequested {
                result.wasCancelled = true
                break
            }

            // The limit counts threads that actually reached Day One (imported
            // or failed) — not loop iterations, so already-imported threads
            // don't eat the budget on a second run.
            if let limit = config.maxThreadsToProcess,
               result.importedCount + result.failedCount >= limit {
                if countPendingImports(Array(plan[i...]), processedIDs: processedIDs) > 0 {
                    log("Stopping after processing \(limit) threads.")
                    result.stoppedAtLimit = true
                }
                break
            }

            switch await importSingleThread(
                planned.thread, processedIDs: &processedIDs, forceReimport: planned.isReimport
            ) {
            case .imported(var entry):
                result.importedCount += 1
                callbacks.progress(result.importedCount, progressTotal)
                if planned.isReimport {
                    entry.previousTweetCount = ThreadSelection.countTweetsBefore(
                        planned.thread, startDate: config.startDate,
                        coveredThrough: config.lastCoveredThrough)
                    reimported.append(entry)
                }
            case .skippedAlreadyImported:
                result.skippedAlreadyImported += 1
            case .skippedNoJournal:
                result.skippedNoJournal += 1
                progressTotal -= 1
                callbacks.progress(result.importedCount, progressTotal)
            case .failed:
                result.failedCount += 1
                progressTotal -= 1
                callbacks.progress(result.importedCount, progressTotal)
            }
        }

        // ---- Step 7: remind the user to delete re-imported duplicates -----
        if !reimported.isEmpty {
            result.reimportReport = ThreadSelection.formatReimportReport(
                reimported, username: config.currentUsername,
                linkHost: config.useXcancelLinks ? XcancelLinks.host : "twitter.com"
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

    /// What happened to one planned thread.
    enum ThreadOutcome {
        case imported(ImportedEntry)
        case skippedAlreadyImported
        /// Skipped by configuration (no reply journal, retweets ignored);
        /// recorded in the ledger so it isn't re-planned next run.
        case skippedNoJournal
        /// Day One rejected the entry; NOT recorded, so the next run retries.
        case failed
    }

    /// Imports one thread into Day One, unless the ledger says it's done.
    ///
    /// With forceReimport, the thread is imported even if it was imported
    /// before — used for threads that grew since their last import.
    private func importSingleThread(
        _ thread: TweetThread,
        processedIDs: inout Set<String>,
        forceReimport: Bool
    ) async -> ThreadOutcome {
        let firstTweet = thread[0]
        let tweetId = firstTweet.idStr

        if processedIDs.contains(tweetId), !forceReimport {
            return .skippedAlreadyImported
        }

        // A re-imported thread is tracked by "<root id>+<last tweet id>", so
        // running the same date range twice doesn't import the same extension
        // over and over.
        let reimportMarker = forceReimport ? ImportLedger.extensionMarker(thread) : nil
        if let marker = reimportMarker {
            if processedIDs.contains(marker) {
                log("Skipping thread \(tweetId): its extension was already imported.")
                return .skippedAlreadyImported
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
            return await ollama.generateTitle(entryText: text, mediaFiles: media)
        }
        guard let targetJournal = EntryComposer.targetJournal(
            category: category, tweetId: tweetId, config: config,
            log: { self.log($0) }
        ) else {
            // Mark as processed even if skipped
            recordProcessed(tweetId: tweetId, reimportMarker: reimportMarker,
                            processedIDs: &processedIDs)
            return .skippedNoJournal
        }

        // Step 6: hand the entry to the Day One CLI — as several entries when
        // the thread carries more attachments than Day One accepts in one.
        logEntryHeader(
            title: title,
            date: content.date ?? firstTweet.createdAt,
            attachments: content.mediaFiles.count
        )

        let parts = ThreadSplitter.split(thread)
        if parts.count > 1 {
            log("Thread \(tweetId) carries \(content.mediaFiles.count) attachments — "
                + "more than Day One's \(ThreadSplitter.maxAttachmentsPerEntry) per entry, "
                + "so it becomes \(parts.count) entries sharing the same date.")
        }
        for (index, part) in parts.enumerated() {
            let partTitle = index == 0 ? title : "\(title) (continued)"
            let partContent = parts.count == 1
                ? content : EntryComposer.aggregateThreadData(part, config: config)
            let entryText = EntryComposer.buildEntryContent(
                entryText: partContent.text, firstTweet: firstTweet, category: category,
                title: partTitle, config: config, isContinuation: index > 0
            )
            callbacks.activity("Saving to “\(targetJournal)”: \(partTitle)")
            let posted = dayOne.addPost(
                text: entryText,
                journal: targetJournal,
                tags: Array(Set(partContent.tags)),
                // Every part carries the thread's start date, so the parts sit
                // together in the journal.
                date: content.date,
                coordinate: partContent.coordinate,
                attachments: partContent.mediaFiles
            )
            guard posted else {
                if index > 0 {
                    log("The first \(index) part(s) of thread \(tweetId) were already "
                        + "saved — the retry will post them again; delete the extra copies.",
                        .warning)
                }
                log("Couldn't save thread \(tweetId) to Day One — it stays unrecorded, "
                    + "so the next run will retry it.", .error)
                callbacks.log("", .info)
                return .failed
            }
        }
        callbacks.log("", .info)

        recordProcessed(tweetId: tweetId, reimportMarker: reimportMarker,
                        processedIDs: &processedIDs)
        return .imported(ImportedEntry(
            tweetId: tweetId,
            title: title,
            category: category,
            journal: targetJournal,
            date: content.date ?? firstTweet.createdAt,
            tweetCount: thread.count
        ))
    }

    /// Writes to the ledger — unless this is a debug run, which must leave no
    /// trace so the listed threads import every time.
    private func recordProcessed(
        tweetId: String, reimportMarker: String?, processedIDs: inout Set<String>
    ) {
        guard config.debugTweetIDs.isEmpty else { return }
        do {
            try ledger.rememberProcessed(
                tweetId: tweetId, reimportMarker: reimportMarker, processedIDs: &processedIDs)
        } catch {
            // The entry is in Day One but its ledger line is not on disk, so a
            // future run will import it again. Keep the in-memory set right for
            // this run's bookkeeping, and make sure the user hears about it.
            processedIDs.insert(tweetId)
            if let reimportMarker { processedIDs.insert(reimportMarker) }
            log("Couldn't record thread \(tweetId) in the import ledger "
                + "(\(error.localizedDescription)) — the entry was created, but the next "
                + "run won't know and will import it again. Check \(ledger.fileURL.path)",
                .error)
        }
    }

    private static let entryDateFormatter = PipelineDates.formatter("dd MMMM yyyy, HH:mm")

    /// The block written to the log for one entry: what it is called, when the
    /// thread was posted, and how much media rides along. The Day One CLI adds
    /// its own "Success:" line right after, and the entry ends with a blank
    /// line — the tweet text itself stays out of the log.
    private func logEntryHeader(title: String, date: Date, attachments: Int) {
        callbacks.log("Title: \(title)", .thread)
        callbacks.log("Tweeted on: \(Self.entryDateFormatter.string(from: date))", .info)
        callbacks.log("Attachments: \(attachments)", .info)
    }

    // MARK: - Pause / cancel plumbing

    /// Cancellation comes through ImportControl (the app runs the engine on a
    /// detached task, which task cancellation can't reach); Task.isCancelled
    /// is honored too for callers that do run the engine as a child task.
    private var cancelRequested: Bool {
        control.isCancelled || Task.isCancelled
    }

    private func waitWhilePaused() async {
        guard control.isPaused else { return }
        callbacks.activity("Paused")
        while control.isPaused && !cancelRequested {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func log(_ message: String, _ kind: ImportLogKind = .info) {
        callbacks.log(message, kind)
    }
}
