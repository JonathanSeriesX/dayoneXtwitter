import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImportViewModel {
    var settings: ImportSettings {
        didSet {
            settings.save()
        }
    }

    var overview: ArchiveOverview?
    var progress = ImportProgressSnapshot(
        totalThreads: 0,
        alreadyImported: 0,
        importedThisRun: 0,
        skippedThisRun: 0,
        failedThisRun: 0,
        currentIndex: 0,
        currentTweetID: nil,
        currentCategory: nil,
        statusMessage: "Drop a Twitter archive folder or zip file to begin."
    )

    var isDropTargeted = false
    var isPreparing = false
    var isImporting = false
    var statusMessage = "Drop a Twitter archive folder or zip file to begin."

    var logLines: [String] = []

    var errorMessage = ""
    var isShowingError = false

    private(set) var activeArchive: ArchiveLocation?

    private let coordinator = ImportCoordinator()
    private var preparedContext: PreparedImportContext?
    private var analysisTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?

    init() {
        self.settings = ImportSettings.load()
    }

    var canImport: Bool {
        preparedContext != nil && !isPreparing && !isImporting
    }

    var hasArchive: Bool {
        preparedContext != nil
    }

    var dateRangeText: String {
        guard let overview else { return "-" }
        guard let first = overview.earliestTweetDate, let last = overview.latestTweetDate else {
            return "-"
        }
        return "\(Self.shortDateFormatter.string(from: first)) - \(Self.shortDateFormatter.string(from: last))"
    }

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.title = "Select Twitter Archive"
        panel.message = "Choose a Twitter archive folder or zip file"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder]

        if panel.runModal() == .OK, let selected = panel.url {
            processDroppedURL(selected)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            setError("Drop a local folder or .zip archive.")
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                Task { @MainActor in
                    self.setError("Failed to read dropped item: \(error.localizedDescription)")
                }
                return
            }

            guard let url = Self.extractFileURL(from: item) else {
                Task { @MainActor in
                    self.setError("Could not decode dropped file URL.")
                }
                return
            }

            Task { @MainActor in
                self.processDroppedURL(url)
            }
        }

        return true
    }

    func processDroppedURL(_ droppedURL: URL) {
        analysisTask?.cancel()
        importTask?.cancel()

        isPreparing = true
        isImporting = false
        statusMessage = "Analyzing archive..."
        appendLog("Analyzing: \(droppedURL.path)")

        let settingsSnapshot = settings

        analysisTask = Task {
            do {
                let context = try await coordinator.resolveAndPrepare(dropURL: droppedURL, settings: settingsSnapshot)
                applyPreparedContext(context)
                statusMessage = "Archive ready: \(context.overview.pendingToImport) pending thread(s)."
                appendLog("Archive ready: \(context.overview.totalTweets) tweets, \(context.overview.threadsInDateRange) thread(s) in date range.")
            } catch {
                setError(error.localizedDescription)
            }

            isPreparing = false
        }
    }

    func refreshPreview() {
        guard let archive = activeArchive else {
            return
        }

        analysisTask?.cancel()
        isPreparing = true
        statusMessage = "Refreshing preview..."

        let settingsSnapshot = settings
        analysisTask = Task {
            do {
                let context = try await coordinator.refresh(archive: archive, settings: settingsSnapshot)
                applyPreparedContext(context)
                statusMessage = "Preview refreshed."
                appendLog("Preview refreshed with updated settings.")
            } catch {
                setError(error.localizedDescription)
            }

            isPreparing = false
        }
    }

    func startImport() {
        guard !isImporting else { return }
        guard let archive = activeArchive else {
            setError("Drop an archive before importing.")
            return
        }

        isImporting = true
        statusMessage = "Preparing import..."
        appendLog("Import started.")

        let settingsSnapshot = settings

        importTask = Task {
            do {
                let context = try await coordinator.refresh(archive: archive, settings: settingsSnapshot)
                applyPreparedContext(context)

                let summary = await coordinator.runImport(context: context, settings: settingsSnapshot) { [weak self] snapshot in
                    Task { @MainActor [weak self] in
                        self?.applyProgress(snapshot)
                    }
                }

                isImporting = false
                if summary.wasCancelled {
                    statusMessage = "Import cancelled."
                    appendLog("Import cancelled after \(summary.attemptedThisRun) thread(s).")
                } else {
                    statusMessage = summary.statusMessage
                    appendLog(summary.statusMessage)
                }

                let refreshed = try await coordinator.refresh(archive: archive, settings: settingsSnapshot)
                applyPreparedContext(refreshed)
            } catch {
                isImporting = false
                setError(error.localizedDescription)
            }
        }
    }

    func cancelImport() {
        guard isImporting else { return }
        importTask?.cancel()
        statusMessage = "Cancelling import..."
        appendLog("Cancellation requested.")
    }

    func resetSettingsToDefaults() {
        settings = ImportSettings()
        appendLog("Settings reset to defaults.")
    }

    func clearLog() {
        logLines.removeAll()
    }

    private func applyPreparedContext(_ context: PreparedImportContext) {
        preparedContext = context
        activeArchive = context.archive
        overview = context.overview

        progress = ImportProgressSnapshot(
            totalThreads: context.overview.threadsInDateRange,
            alreadyImported: context.overview.alreadyImported,
            importedThisRun: 0,
            skippedThisRun: 0,
            failedThisRun: 0,
            currentIndex: 0,
            currentTweetID: nil,
            currentCategory: nil,
            statusMessage: "Ready"
        )
    }

    private func applyProgress(_ snapshot: ImportProgressSnapshot) {
        progress = snapshot
        statusMessage = snapshot.statusMessage

        if let tweetID = snapshot.currentTweetID {
            appendLog("\(tweetID): \(snapshot.statusMessage)")
        } else {
            appendLog(snapshot.statusMessage)
        }
    }

    private func setError(_ message: String) {
        errorMessage = message
        isShowingError = true
        statusMessage = "Error"
        appendLog("Error: \(message)")
        isPreparing = false
        isImporting = false
    }

    private func appendLog(_ line: String) {
        let timestamp = Self.logTimestampFormatter.string(from: Date())
        logLines.append("[\(timestamp)] \(line)")
        if logLines.count > 250 {
            logLines.removeFirst(logLines.count - 250)
        }
    }

    nonisolated private static func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let text = item as? String {
            return URL(string: text)
        }

        return nil
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
