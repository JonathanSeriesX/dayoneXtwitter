import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum WizardStep: Int, CaseIterable, Identifiable, Sendable {
    case drop
    case prerequisites
    case settings
    case progress
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .drop:
            return "Drop Archive"
        case .prerequisites:
            return "Prerequisites"
        case .settings:
            return "Import Settings"
        case .progress:
            return "Import Progress"
        case .done:
            return "Finished"
        }
    }

    var shortLabel: String {
        switch self {
        case .drop:
            return "1"
        case .prerequisites:
            return "2"
        case .settings:
            return "3"
        case .progress:
            return "4"
        case .done:
            return "5"
        }
    }
}

enum PrerequisiteState: Sendable {
    case passed
    case warning
    case failed
    case checking

    var symbolName: String {
        switch self {
        case .passed:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .checking:
            return "clock.fill"
        }
    }

    var statusLabel: String {
        switch self {
        case .passed:
            return "Ready"
        case .warning:
            return "Attention"
        case .failed:
            return "Missing"
        case .checking:
            return "Checking"
        }
    }
}

struct PrerequisiteCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let details: String
    let isRequired: Bool
    let state: PrerequisiteState
}

@MainActor
@Observable
final class ImportViewModel {
    var settings: ImportSettings {
        didSet {
            settings.save()
        }
    }

    var currentStep: WizardStep = .drop
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
    var isCheckingPrerequisites = false
    var statusMessage = "Drop a Twitter archive folder or zip file to begin."

    var preflightChecks: [PrerequisiteCheck]
    var logLines: [String] = []

    var errorMessage = ""
    var isShowingError = false

    var lastRunSummary: ImportRunSummary?

    private(set) var activeArchive: ArchiveLocation?

    private let coordinator = ImportCoordinator()
    private var preparedContext: PreparedImportContext?
    private var analysisTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var checksTask: Task<Void, Never>?

    init() {
        let loadedSettings = ImportSettings.load()
        self.settings = loadedSettings
        self.preflightChecks = Self.placeholderChecks(llmEnabled: loadedSettings.processTitlesWithLLM)
    }

    var canImport: Bool {
        preparedContext != nil && !isPreparing && !isImporting && hasMetRequiredPrerequisites
    }

    var hasArchive: Bool {
        preparedContext != nil
    }

    var canProceedFromDrop: Bool {
        hasArchive && !isPreparing
    }

    var canProceedFromPrerequisites: Bool {
        hasMetRequiredPrerequisites && !isCheckingPrerequisites
    }

    var detectedUsername: String? {
        overview?.archiveUsername
    }

    var detectedDisplayName: String? {
        overview?.archiveDisplayName
    }

    var hasMetRequiredPrerequisites: Bool {
        let required = preflightChecks.filter(\.isRequired)
        guard !required.isEmpty else { return false }
        return required.allSatisfy { $0.state == .passed }
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
        checksTask?.cancel()

        isPreparing = true
        isImporting = false
        currentStep = .drop
        statusMessage = "Analyzing archive..."
        appendLog("Analyzing: \(droppedURL.path)")

        let settingsSnapshot = settings

        analysisTask = Task {
            do {
                let context = try await coordinator.resolveAndPrepare(dropURL: droppedURL, settings: settingsSnapshot)
                applyPreparedContext(context)
                statusMessage = "Archive ready: \(context.overview.pendingToImport) pending thread(s)."
                appendLog("Archive ready: \(context.overview.totalTweets) tweets, \(context.overview.threadsInDateRange) thread(s) in date range.")

                currentStep = .prerequisites
                runPrerequisiteChecks()
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
                runPrerequisiteChecks()
            } catch {
                setError(error.localizedDescription)
            }

            isPreparing = false
        }
    }

    func runPrerequisiteChecks() {
        checksTask?.cancel()
        isCheckingPrerequisites = true
        preflightChecks = Self.placeholderChecks(llmEnabled: settings.processTitlesWithLLM)

        let settingsSnapshot = settings
        let hasArchive = activeArchive != nil

        checksTask = Task {
            let checks = await Self.evaluatePrerequisites(settings: settingsSnapshot, hasArchive: hasArchive)
            guard !Task.isCancelled else { return }
            self.preflightChecks = checks
            self.isCheckingPrerequisites = false
        }
    }

    func goToPrerequisitesStep() {
        currentStep = .prerequisites
        if !isCheckingPrerequisites {
            runPrerequisiteChecks()
        }
    }

    func goToSettingsStep() {
        guard canProceedFromPrerequisites else {
            setError("Please satisfy required prerequisites before continuing.")
            return
        }
        currentStep = .settings
    }

    func goBackFromSettings() {
        currentStep = .prerequisites
    }

    func goBackFromProgress() {
        guard !isImporting else { return }
        currentStep = .settings
    }

    func restartWithNewArchive() {
        analysisTask?.cancel()
        importTask?.cancel()
        checksTask?.cancel()

        activeArchive = nil
        preparedContext = nil
        overview = nil
        lastRunSummary = nil
        preflightChecks = Self.placeholderChecks(llmEnabled: settings.processTitlesWithLLM)
        progress = ImportProgressSnapshot(
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
        statusMessage = "Drop a Twitter archive folder or zip file to begin."
        currentStep = .drop
        appendLog("Reset flow. Waiting for a new archive.")
    }

    func startImport() {
        guard !isImporting else { return }
        guard let archive = activeArchive else {
            setError("Drop an archive before importing.")
            return
        }

        guard hasMetRequiredPrerequisites else {
            currentStep = .prerequisites
            setError("Required prerequisites are not satisfied.")
            return
        }

        isImporting = true
        currentStep = .progress
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
                lastRunSummary = summary

                if summary.wasCancelled {
                    statusMessage = "Import cancelled."
                    appendLog("Import cancelled after \(summary.attemptedThisRun) thread(s).")
                    currentStep = .settings
                } else {
                    statusMessage = summary.statusMessage
                    appendLog(summary.statusMessage)
                    currentStep = .done
                }

                let refreshed = try await coordinator.refresh(archive: archive, settings: settingsSnapshot)
                applyPreparedContext(refreshed)
            } catch {
                isImporting = false
                currentStep = .settings
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
        runPrerequisiteChecks()
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
        if logLines.count > 350 {
            logLines.removeFirst(logLines.count - 350)
        }
    }

    private static func placeholderChecks(llmEnabled: Bool) -> [PrerequisiteCheck] {
        var checks: [PrerequisiteCheck] = [
            PrerequisiteCheck(
                id: "archive",
                title: "Archive selected",
                details: "Waiting for archive",
                isRequired: true,
                state: .checking
            ),
            PrerequisiteCheck(
                id: "dayone-app",
                title: "Day One app installed",
                details: "Checking /Applications",
                isRequired: true,
                state: .checking
            ),
            PrerequisiteCheck(
                id: "dayone-cli",
                title: "Day One CLI installed",
                details: "Checking dayone executable",
                isRequired: true,
                state: .checking
            ),
            PrerequisiteCheck(
                id: "journals",
                title: "Target journals available",
                details: "Checking configured journals",
                isRequired: false,
                state: .checking
            )
        ]

        if llmEnabled {
            checks += [
                PrerequisiteCheck(
                    id: "ollama-install",
                    title: "Ollama installed",
                    details: "Checking ollama command",
                    isRequired: false,
                    state: .checking
                ),
                PrerequisiteCheck(
                    id: "ollama-service",
                    title: "Ollama service reachable",
                    details: "Checking \(ImportSettings().ollamaAPIURL)",
                    isRequired: false,
                    state: .checking
                ),
                PrerequisiteCheck(
                    id: "ollama-model",
                    title: "Ollama model present",
                    details: "Checking configured model",
                    isRequired: false,
                    state: .checking
                )
            ]
        } else {
            checks.append(
                PrerequisiteCheck(
                    id: "ollama-disabled",
                    title: "LLM title generation",
                    details: "Disabled in settings. Ollama checks skipped.",
                    isRequired: false,
                    state: .passed
                )
            )
        }

        return checks
    }

    private static func evaluatePrerequisites(settings: ImportSettings, hasArchive: Bool) async -> [PrerequisiteCheck] {
        var checks: [PrerequisiteCheck] = []

        checks.append(
            PrerequisiteCheck(
                id: "archive",
                title: "Archive selected",
                details: hasArchive ? "Archive is loaded and parsed." : "Drop or choose an archive first.",
                isRequired: true,
                state: hasArchive ? .passed : .failed
            )
        )

        let dayOnePaths = [
            "/Applications/Day One.app",
            "\(NSHomeDirectory())/Applications/Day One.app"
        ]

        let dayOnePath = dayOnePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        checks.append(
            PrerequisiteCheck(
                id: "dayone-app",
                title: "Day One app installed",
                details: dayOnePath ?? "Install Day One from the Mac App Store.",
                isRequired: true,
                state: dayOnePath == nil ? .failed : .passed
            )
        )

        let dayOneCLI = DayOneCLI()
        let dayOneExecutable = dayOneCLI.installedExecutablePath()
        checks.append(
            PrerequisiteCheck(
                id: "dayone-cli",
                title: "Day One CLI installed",
                details: dayOneExecutable ?? "Follow Day One CLI guide and ensure 'dayone' is in PATH.",
                isRequired: true,
                state: dayOneExecutable == nil ? .failed : .passed
            )
        )

        if dayOneExecutable != nil {
            let journalCheck = dayOneCLI.listJournals()
            if let journalLines = journalCheck.journals {
                let hasTweets = containsJournal(named: settings.journalName, within: journalLines)
                let hasReplies = !settings.includeReplies || containsJournal(named: settings.replyJournalName, within: journalLines)
                let details: String
                let state: PrerequisiteState

                if hasTweets && hasReplies {
                    details = "Configured journals are available."
                    state = .passed
                } else if hasTweets {
                    details = "Reply journal '\(settings.replyJournalName)' is missing."
                    state = .warning
                } else {
                    details = "Journal '\(settings.journalName)' was not found."
                    state = .warning
                }

                checks.append(
                    PrerequisiteCheck(
                        id: "journals",
                        title: "Target journals available",
                        details: details,
                        isRequired: false,
                        state: state
                    )
                )
            } else {
                let detail = journalCheck.error ?? "Unknown error"
                checks.append(
                    PrerequisiteCheck(
                        id: "journals",
                        title: "Target journals available",
                        details: "Could not verify journals: \(detail)",
                        isRequired: false,
                        state: .warning
                    )
                )
            }
        } else {
            checks.append(
                PrerequisiteCheck(
                    id: "journals",
                    title: "Target journals available",
                    details: "Skipped because Day One CLI is missing.",
                    isRequired: false,
                    state: .warning
                )
            )
        }

        if settings.processTitlesWithLLM {
            let ollamaPath = pathForCommand("ollama")
            checks.append(
                PrerequisiteCheck(
                    id: "ollama-install",
                    title: "Ollama installed",
                    details: ollamaPath ?? "Install Ollama if you want automatic thread titles.",
                    isRequired: false,
                    state: ollamaPath == nil ? .warning : .passed
                )
            )

            if ollamaPath != nil {
                let apiReachable = await isOllamaAPIReachable(apiURL: settings.ollamaAPIURL)
                checks.append(
                    PrerequisiteCheck(
                        id: "ollama-service",
                        title: "Ollama service reachable",
                        details: apiReachable
                            ? "Ollama API responded at \(settings.ollamaAPIURL)."
                            : "Ollama API did not respond. Start Ollama or run 'ollama serve'.",
                        isRequired: false,
                        state: apiReachable ? .passed : .warning
                    )
                )

                let hasModel = ollamaModelExists(modelName: settings.ollamaModelName)
                checks.append(
                    PrerequisiteCheck(
                        id: "ollama-model",
                        title: "Ollama model present",
                        details: hasModel
                            ? "Model '\(settings.ollamaModelName)' is available."
                            : "Model '\(settings.ollamaModelName)' not found. Pull it before importing.",
                        isRequired: false,
                        state: hasModel ? .passed : .warning
                    )
                )
            } else {
                checks.append(
                    PrerequisiteCheck(
                        id: "ollama-service",
                        title: "Ollama service reachable",
                        details: "Skipped because Ollama is not installed.",
                        isRequired: false,
                        state: .warning
                    )
                )
                checks.append(
                    PrerequisiteCheck(
                        id: "ollama-model",
                        title: "Ollama model present",
                        details: "Skipped because Ollama is not installed.",
                        isRequired: false,
                        state: .warning
                    )
                )
            }
        } else {
            checks.append(
                PrerequisiteCheck(
                    id: "ollama-disabled",
                    title: "LLM title generation",
                    details: "Disabled in settings. Ollama checks skipped.",
                    isRequired: false,
                    state: .passed
                )
            )
        }

        return checks
    }

    private static func containsJournal(named expectedName: String, within lines: [String]) -> Bool {
        let expected = expectedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expected.isEmpty else { return false }

        return lines.contains { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if line == expected {
                return true
            }
            if line.hasPrefix("\(expected) (") {
                return true
            }
            if line.contains("\"\(expected)\"") {
                return true
            }
            return false
        }
    }

    private static func isOllamaAPIReachable(apiURL: String) async -> Bool {
        guard let baseURL = URL(string: apiURL),
              let host = baseURL.host,
              let scheme = baseURL.scheme
        else {
            return false
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = baseURL.port ?? 11434
        components.path = "/api/tags"

        guard let tagsURL = components.url else {
            return false
        }

        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ... 299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private static func ollamaModelExists(modelName: String) -> Bool {
        let result = runCommand(executablePath: "/usr/bin/env", arguments: ["ollama", "list"])
        guard result.exitCode == 0 else {
            return false
        }

        let expected = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expected.isEmpty else { return false }

        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(where: { line in
                line.hasPrefix(expected + " ") || line.hasPrefix(expected + "\t") || line.hasPrefix(expected + ":")
            })
    }

    private static func pathForCommand(_ command: String) -> String? {
        let result = runCommand(executablePath: "/usr/bin/which", arguments: [command])
        guard result.exitCode == 0 else {
            return nil
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func runCommand(executablePath: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
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

            return (
                process.terminationStatus,
                String(data: stdoutData, encoding: .utf8) ?? "",
                String(data: stderrData, encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "", error.localizedDescription)
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
