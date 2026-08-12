// The app's state machine: drop → configure → import → done. Owns the loaded
// archive, drives the import engine on a background task, and relays its
// progress to the UI.

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
        case importing
        case done

        var title: String {
            switch self {
            case .drop: return "Archive"
            case .configure: return "Configure"
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
    @Published var activity = ""
    @Published var logLines: [LogLine] = []
    @Published var runResult: ImportRunResult?

    let settings = AppSettings()
    let control = ImportControl()
    /// Threads must be categorized at most once per loaded archive, even
    /// across several runs — categorization mutates the tweet text.
    private var categoryCache = ImportEngine.CategoryCache()
    private var importTask: Task<Void, Never>?
    private var logCounter = 0

    /// The resolved Day One CLI binary, re-checked when the configure screen appears.
    @Published var dayOneBinary: String? = DayOneCLI.resolveBinary()

    func refreshDayOneBinary() {
        dayOneBinary = DayOneCLI.resolveBinary()
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
        logLines = []

        // A fresh archive knows the account's username — prefill it, the user
        // can still edit or clear it.
        if settings.currentUsername.isEmpty, let username = loaded.archiveUsername {
            settings.currentUsername = username
        }
        refreshDayOneBinary()
        step = .configure
    }

    // MARK: - Steps 4–7: the import run

    var ledger: ImportLedger? {
        archive.map { ImportLedger(accountId: $0.accountId) }
    }

    func startImport() {
        guard let archive, let binary = dayOneBinary, importTask == nil else { return }

        let config = settings.buildConfig()
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
            dayOne: DayOneCLI(binaryPath: binary, log: { log($0, .info) }),
            ollama: config.processTitlesWithLLM
                ? OllamaClient(settings: .init(config: config), log: { log($0, .warning) })
                : nil,
            categoryCache: categoryCache,
            control: control,
            callbacks: ImportCallbacks(
                log: log,
                progress: { [weak self] imported, total in
                    Task { @MainActor [weak self] in
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
        activity = "Selecting threads…"
        logLines = []
        runResult = nil
        control.setPaused(false)
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
        control.setPaused(false)
        runResult = result
        saveReportIfAny(result)
        step = .done
    }

    func togglePause() {
        isPaused.toggle()
        control.setPaused(isPaused)
        if !isPaused {
            activity = "Resuming…"
        }
    }

    func cancelImport() {
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
        guard !isImporting else { return }
        step = .configure
    }

    func startOver() {
        guard !isImporting else { return }
        archive = nil
        loadError = nil
        runResult = nil
        logLines = []
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
}
