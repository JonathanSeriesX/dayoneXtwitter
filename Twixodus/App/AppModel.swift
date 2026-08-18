// The app's state machine: drop → configure → retrieve → import → done. Owns
// the loaded archive, drives the retrieval and import engines on background
// tasks, and relays their progress to the UI.

import AppKit
import Foundation
import SwiftUI

struct LogLine: Identifiable {
    let id: Int
    let text: String
    let kind: ImportLogKind
}

@MainActor
final class AppModel: ObservableObject {

    enum Step: Int, CaseIterable {
        case drop = 0
        case configure
        case retrieve
        case importing
        case done

        var title: String {
            switch self {
            case .drop: return "Archive"
            case .configure: return "Configure"
            case .retrieve: return "Retrieve"
            case .importing: return "Import"
            case .done: return "Done"
            }
        }
    }

    @Published var step: Step = .drop

    // MARK: - Archive loading

    @Published var isLoadingArchive = false
    @Published var loadStage = ""
    @Published var loadError: String?
    @Published var archive: LoadedArchive?

    // MARK: - Import run

    @Published var isImporting = false
    @Published var isPaused = false
    @Published var importedCount = 0
    @Published var totalPending = 0
    /// False until the engine reports its first progress (i.e. while it is
    /// still selecting threads). The denominator can legitimately shrink to
    /// zero later — this flag keeps the UI from reading that as "not started".
    @Published var progressStarted = false
    @Published var activity = ""
    /// The import run's log (and the archive-loading messages before it).
    @Published var logLines: [LogLine] = []
    @Published var runResult: ImportRunResult?
    /// What the next run will do with the loaded archive — recomputed once per
    /// event (archive loaded, run finished), not on every render.
    @Published var importPreview: ImportPreview?
    /// How far previous completed runs of this account got, from ImportHistory.
    @Published var lastCoveredDate: Date?
    /// Whether a ledger or history file exists for this account — gates the
    /// "reset previous run data" button.
    @Published var hasPreviousRunData = false

    // MARK: - Retrieval run (the Retrieve step)

    @Published var hydrationPlan: HydrationPlan?
    /// How many tweets the scan covered — i.e. what the next import will
    /// touch, which is what the Retrieve screen promises to fill in.
    @Published var retrieveScope = 0
    @Published var isRetrieving = false
    @Published var retrieveDone = 0
    @Published var retrieveTotal = 0
    /// One-line summary of the last completed retrieval run, for the UI.
    @Published var retrieveSummary: String?
    /// Whether that run left anything worth a second look — the summary is
    /// shown in orange rather than green.
    @Published var retrieveHadTrouble = false
    /// The retrieval run's own log, kept apart from the import's so the
    /// Retrieve screen only ever shows tweets being fetched and downloaded —
    /// never the archive-loading notes or a later import's entries.
    @Published var retrieveLog: [LogLine] = []
    private(set) var hydrationStore: HydrationStore?
    private var retrieveTask: Task<Void, Never>?
    /// The tweets the last scan covered — kept so a retry can re-plan over
    /// exactly the same scope without redoing the thread selection.
    private var hydrationScopeTweets: [Tweet] = []

    let settings = AppSettings()
    let control = ImportControl()
    /// Threads must be categorized at most once per loaded archive, even
    /// across several runs — categorization mutates the tweet text.
    private var categoryCache = ImportEngine.CategoryCache()
    private var importTask: Task<Void, Never>?
    private var logCounter = 0

    /// The resolved Day One CLI binary, re-checked when the configure screen appears.
    @Published var dayOneBinary: String? = DayOneCLI.resolveBinary()
    /// Where the Day One app itself is installed, if anywhere.
    @Published var dayOneAppURL: URL? = NSWorkspace.shared
        .urlForApplication(withBundleIdentifier: AppModel.dayOneBundleID)

    static let dayOneBundleID = "com.bloombuilt.dayone-mac"

    func refreshDayOneBinary() {
        dayOneBinary = DayOneCLI.resolveBinary()
        dayOneAppURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: Self.dayOneBundleID)
    }

    // MARK: - Step 0: taking the dropped archive

    func handleDropped(url: URL) {
        guard !isLoadingArchive else { return }
        isLoadingArchive = true
        loadError = nil
        loadStage = ZipExtractor.isZip(url) ? "Extracting the archive…" : "Reading tweets…"

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                var root = url
                if ZipExtractor.isZip(url) {
                    root = try ZipExtractor.extract(url)
                }
                let loaded = try ArchiveLoading.load(
                    root: root,
                    stage: { stage in
                        Task { @MainActor [weak self] in self?.loadStage = stage }
                    },
                    log: { message in
                        Task { @MainActor [weak self] in self?.appendLog(message, .info) }
                    }
                )
                await MainActor.run { [weak self] in
                    self?.archiveLoaded(loaded)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isLoadingArchive = false
                    self?.loadError = error.localizedDescription
                }
            }
        }
    }

    private func archiveLoaded(_ loaded: LoadedArchive) {
        isLoadingArchive = false
        archive = loaded
        categoryCache = ImportEngine.CategoryCache()
        runResult = nil
        retrieveSummary = nil
        hydrationStore = {
            let store = HydrationStore(for: loaded.ref)
            if store.exists { store.load() }
            return store
        }()
        lastCoveredDate = ImportHistory(accountId: loaded.accountId).load()?.coveredThrough
        refreshImportPreview()

        refreshDayOneBinary()
        step = .configure
    }

    // MARK: - The Retrieve step

    func goToRetrieve() {
        guard !isImporting, !isRetrieving else { return }
        refreshHydrationPlan()
        step = .retrieve
    }

    /// Rescans the archive against the hydration store. Cheap enough to run
    /// per event (step entered, run finished), like refreshImportPreview.
    func refreshHydrationPlan() {
        guard let archive, let hydrationStore else {
            hydrationPlan = nil
            return
        }
        // Retrieval covers exactly what the next import will touch — not the
        // whole archive. Everything that narrows a run narrows this too: the
        // ledger, the date range, the debug ID list, the per-run limit and
        // its order, plus threads the config skips outright (retweets when
        // they're off, replies with no reply journal).
        var config = settings.buildConfig()
        config.lastCoveredThrough = lastCoveredDate
        let processedIDs = config.debugTweetIDs.isEmpty
            ? (ledger?.loadProcessedIDs() ?? []) : []
        let runPlan = ThreadSelection.planRun(
            archive.threads, config: config, processedIDs: processedIDs)
        let tweets = ThreadSelection
            .threadsThisRunWillImport(runPlan.imports, processedIDs: processedIDs,
                                      limit: config.maxThreadsToProcess)
            .filter { !ThreadCategorizer.isSkippedByConfig($0, config: config) }
            .flatMap { $0 }

        hydrationScopeTweets = tweets
        hydrationPlan = HydrationPlanner.plan(
            tweets: tweets,
            ownTweetIDs: archive.ownTweetIDs,
            archiveUsername: archive.archiveUsername,
            store: hydrationStore)
        retrieveScope = tweets.count
    }

    /// Runs the retrieval. With retryingFailures, the plan also picks up
    /// everything the store recorded as gone or half-finished — a 404 from
    /// this endpoint isn't always the last word, and an attachment that
    /// failed to download deserves another go.
    func startRetrieval(retryingFailures: Bool = false) {
        guard let hydrationStore, retrieveTask == nil, !isImporting else { return }
        refreshHydrationPlan()
        var plan = hydrationPlan
        if retryingFailures, let archive {
            plan = HydrationPlanner.plan(
                tweets: hydrationScopeTweets,
                ownTweetIDs: archive.ownTweetIDs,
                archiveUsername: archive.archiveUsername,
                store: hydrationStore,
                retrying: true)
        }
        guard let plan, plan.totalPending > 0 else { return }

        isRetrieving = true
        isPaused = false
        retrieveDone = 0
        retrieveTotal = plan.totalPending
        retrieveSummary = nil
        activity = "Starting retrieval…"
        retrieveLog = []
        control.reset()

        let engine = HydrationEngine(
            store: hydrationStore,
            control: control,
            callbacks: ImportCallbacks(
                log: { [weak self] message, kind in
                    Task { @MainActor [weak self] in self?.appendRetrieveLog(message, kind) }
                },
                progress: { [weak self] done, total in
                    Task { @MainActor [weak self] in
                        self?.retrieveDone = done
                        self?.retrieveTotal = total
                    }
                },
                activity: { [weak self] activity in
                    Task { @MainActor [weak self] in self?.activity = activity }
                }
            )
        )

        retrieveTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                await engine.run(plan: plan)
            }.value
            await MainActor.run { [weak self] in
                self?.retrievalFinished(result)
            }
        }
    }

    private func retrievalFinished(_ result: HydrationRunResult) {
        retrieveTask = nil
        isRetrieving = false
        isPaused = false
        control.reset()

        // Fold the fetched data into the loaded tweets right away, so the
        // import that follows uses it.
        if let archive, let hydrationStore {
            HydrationOverlay.apply(tweets: archive.tweets, store: hydrationStore)
        }
        refreshHydrationPlan()

        var parts: [String] = []
        if result.retweetsRetrieved > 0 { parts.append("\(result.retweetsRetrieved) retweets un-truncated") }
        if result.quotesRetrieved > 0 { parts.append("\(result.quotesRetrieved) quoted tweets retrieved") }
        if result.filesDownloaded > 0 { parts.append("\(result.filesDownloaded) files downloaded") }
        if result.unavailable > 0 { parts.append("\(result.unavailable) tweets turned out gone") }
        if result.incomplete > 0 { parts.append("\(result.incomplete) missing some attachments") }
        if result.failures > 0 { parts.append("\(result.failures) requests failed") }
        var summary = parts.isEmpty ? "Nothing new was retrieved" : parts.joined(separator: ", ")
        if result.wasCancelled { summary = "Cancelled — \(summary)" }
        if result.abortedByErrors { summary = "Stopped early (rate-limited?) — \(summary)" }
        retrieveSummary = summary
        retrieveHadTrouble = result.wasCancelled || result.abortedByErrors
            || result.failures > 0 || result.incomplete > 0
        appendRetrieveLog(summary, .info)
        activity = ""
    }

    func cancelRetrieval() {
        control.cancel()
        retrieveTask?.cancel()
        control.setPaused(false)
        isPaused = false
    }

    // MARK: - Steps 4–7: the import run

    var ledger: ImportLedger? {
        archive.map { ImportLedger(accountId: $0.accountId) }
    }

    /// Recomputes what the next run would import. Walks all threads against
    /// the ledger, so it's called per event, never from a SwiftUI body.
    func refreshImportPreview() {
        guard let archive, let ledger else {
            importPreview = nil
            hasPreviousRunData = false
            return
        }
        let config = settings.buildConfig()
        var threads = archive.threads
        var processedIDs = ledger.loadProcessedIDs()
        var coveredThrough = lastCoveredDate
        if !config.debugTweetIDs.isEmpty {
            // Debug runs import the listed threads every time, ledger ignored.
            threads = ThreadSelection.filterToDebugIDs(threads, ids: config.debugTweetIDs)
            processedIDs = []
            coveredThrough = nil
        }
        importPreview = ThreadSelection.preview(
            threads, startDate: config.startDate, endDate: config.endDate,
            processedIDs: processedIDs,
            coveredThrough: coveredThrough)
        let fm = FileManager.default
        hasPreviousRunData = fm.fileExists(atPath: ledger.fileURL.path)
            || fm.fileExists(atPath: ImportHistory(accountId: archive.accountId).fileURL.path)
    }

    /// Forgets everything about previous runs of this account: the ledger, the
    /// coverage record, and the saved delete-the-duplicates report. Entries
    /// already in Day One are untouched — the next run imports everything
    /// again, duplicating whatever is already there.
    func resetPreviousRunData() {
        guard let archive, !isImporting else { return }
        let fm = FileManager.default
        if let ledger { try? fm.removeItem(at: ledger.fileURL) }
        try? fm.removeItem(at: ImportHistory(accountId: archive.accountId).fileURL)
        try? fm.removeItem(at: Self.reportFileURL)
        lastCoveredDate = nil
        refreshImportPreview()
    }

    func startImport() {
        guard let archive, let binary = dayOneBinary, importTask == nil else { return }

        var config = settings.buildConfig()
        // The username comes straight from the archive; links back to the
        // tweets only make sense while the account still exists.
        config.currentUsername = settings.accountStillExists
            ? archive.archiveUsername?.pyTrimmedOrNil() : nil
        // Lets the run spot already-imported threads that grew since the last
        // import — including ones rooted on the resume range's overlap day.
        config.lastCoveredThrough = lastCoveredDate
        let context = ThreadCategorizer.Context(
            ownTweetIDs: archive.ownTweetIDs,
            currentUsername: config.currentUsername
        )
        let log: (String, ImportLogKind) -> Void = { [weak self] message, kind in
            Task { @MainActor [weak self] in self?.appendLog(message, kind) }
        }
        let engine = ImportEngine(
            config: config,
            context: context,
            ledger: ImportLedger(accountId: archive.accountId),
            dayOne: DayOneCLI(binaryPath: binary, log: log),
            ollama: config.processTitlesWithLLM
                ? OllamaClient(settings: .init(config: config), log: { log($0, .warning) })
                : nil,
            categoryCache: categoryCache,
            control: control,
            callbacks: ImportCallbacks(
                log: log,
                progress: { [weak self] imported, total in
                    Task { @MainActor [weak self] in
                        self?.progressStarted = true
                        self?.importedCount = imported
                        self?.totalPending = total
                    }
                },
                activity: { [weak self] activity in
                    Task { @MainActor [weak self] in self?.activity = activity }
                }
            )
        )

        isImporting = true
        isPaused = false
        importedCount = 0
        totalPending = 0
        progressStarted = false
        activity = "Selecting threads…"
        logLines = []
        runResult = nil
        control.reset()
        step = .importing

        let threads = archive.threads
        importTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                await engine.run(threads: threads)
            }.value
            await MainActor.run { [weak self] in
                self?.importFinished(result)
            }
        }
    }

    private func importFinished(_ result: ImportRunResult) {
        importTask = nil
        isImporting = false
        isPaused = false
        control.reset()
        runResult = result
        saveReportIfAny(result)
        recordCoverage(result)
        refreshImportPreview()
        step = .done
    }

    /// After a fully completed run, remembers how far the imports now reach —
    /// but only when nothing was cut off by a cancel, the per-run limit, or a
    /// failure, so the record never claims coverage the run didn't deliver.
    private func recordCoverage(_ result: ImportRunResult) {
        // A debug-narrowed run (date range, specific tweets) never saw the
        // whole archive, so it can't vouch for coverage.
        guard let archive, !settings.debugFiltersActive,
              !result.wasCancelled, !result.stoppedAtLimit, result.failedCount == 0,
              let newestTweet = archive.tweets.map(\.createdAt).max()
        else { return }
        // A completed run went over the whole archive, so the coverage point
        // is simply the newest tweet the archive holds.
        let history = ImportHistory(accountId: archive.accountId)
        history.recordCovered(through: newestTweet)
        lastCoveredDate = history.load()?.coveredThrough
    }

    /// Shared by the import and retrieval runs — only one runs at a time.
    func togglePause() {
        isPaused.toggle()
        control.setPaused(isPaused)
        if !isPaused {
            activity = "Resuming…"
        }
    }

    func cancelImport() {
        // The engine runs on a detached task, which task cancellation can't
        // reach — the lock-backed flag is what actually stops the loop.
        control.cancel()
        importTask?.cancel()
        control.setPaused(false)
        isPaused = false
    }

    // MARK: - The re-import report

    static var reportFileURL: URL {
        ImportLedger.appSupportFolder.appendingPathComponent("threads_to_delete.txt")
    }

    /// The delete-the-duplicates reminder is also saved to Application Support,
    /// so it survives the window being closed.
    private func saveReportIfAny(_ result: ImportRunResult) {
        guard let report = result.reimportReport else { return }
        try? FileManager.default.createDirectory(
            at: ImportLedger.appSupportFolder, withIntermediateDirectories: true)
        try? report.write(to: Self.reportFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Navigation

    func backToConfigure() {
        guard !isImporting, !isRetrieving else { return }
        step = .configure
    }

    func startOver() {
        guard !isImporting, !isRetrieving else { return }
        archive = nil
        loadError = nil
        runResult = nil
        logLines = []
        retrieveLog = []
        hydrationStore = nil
        hydrationPlan = nil
        retrieveSummary = nil
        step = .drop
    }

    // MARK: - Logging

    private func appendLog(_ message: String, _ kind: ImportLogKind) {
        logCounter += 1
        logLines.append(LogLine(id: logCounter, text: message, kind: kind))
        // The log is a live view, not an archive — keep it from growing without bound.
        if logLines.count > 1200 {
            logLines.removeFirst(400)
        }
    }

    private func appendRetrieveLog(_ message: String, _ kind: ImportLogKind) {
        // One counter for both logs, so their line IDs can't collide.
        logCounter += 1
        retrieveLog.append(LogLine(id: logCounter, text: message, kind: kind))
        if retrieveLog.count > 1200 {
            retrieveLog.removeFirst(400)
        }
    }
}
