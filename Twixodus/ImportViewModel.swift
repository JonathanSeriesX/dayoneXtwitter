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
            return AppStrings.Wizard.drop
        case .prerequisites:
            return AppStrings.Wizard.prerequisites
        case .settings:
            return AppStrings.Wizard.settings
        case .progress:
            return AppStrings.Wizard.progress
        case .done:
            return AppStrings.Wizard.done
        }
    }

    var shortLabel: String {
        switch self {
        case .drop:
            return AppStrings.Wizard.dropShort
        case .prerequisites:
            return AppStrings.Wizard.prerequisitesShort
        case .settings:
            return AppStrings.Wizard.settingsShort
        case .progress:
            return AppStrings.Wizard.progressShort
        case .done:
            return AppStrings.Wizard.doneShort
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
            return AppStrings.ViewModel.readyStatus
        case .warning:
            return AppStrings.ViewModel.attentionStatus
        case .failed:
            return AppStrings.ViewModel.missingStatus
        case .checking:
            return AppStrings.ViewModel.checkingStatus
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
    var settings: ImportSettings

    var currentStep: WizardStep = .drop
    var overview: ArchiveOverview?
    var progress = ImportViewModel.emptyProgressSnapshot(statusMessage: AppStrings.ViewModel.initialStatus)

    var isDropTargeted = false
    var isPreparing = false
    var isRefreshingPreview = false
    var isImporting = false
    var isCheckingPrerequisites = false
    var statusMessage = AppStrings.ViewModel.initialStatus

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
    private var archivePrepareSequence = 0
    private var previewRefreshSequence = 0
    private var cachedDayOneAppCheck: PrerequisiteCheck?
    private var cachedDayOneCLICheck: PrerequisiteCheck?

    init() {
        self.settings = ImportSettings()
        self.preflightChecks = Self.placeholderChecks()
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
        guard let overview else { return AppStrings.ViewModel.dash }
        guard let first = overview.earliestTweetDate, let last = overview.latestTweetDate else {
            return AppStrings.ViewModel.dash
        }
        return "\(Self.shortDateFormatter.string(from: first)) - \(Self.shortDateFormatter.string(from: last))"
    }

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.ViewModel.selectArchiveTitle
        panel.message = AppStrings.ViewModel.selectArchiveMessage
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
            setError(AppStrings.ViewModel.dropInvalidItem)
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                Task { @MainActor in
                    self.setError(AppStrings.ViewModel.failedToReadDroppedItem(error.localizedDescription))
                }
                return
            }

            guard let url = Self.extractFileURL(from: item) else {
                Task { @MainActor in
                    self.setError(AppStrings.ViewModel.failedToDecodeDroppedURL)
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
        archivePrepareSequence += 1
        let prepareSequence = archivePrepareSequence
        analysisTask?.cancel()
        importTask?.cancel()
        checksTask?.cancel()

        preparedContext = nil
        activeArchive = nil
        overview = nil
        cachedDayOneAppCheck = nil
        cachedDayOneCLICheck = nil

        isPreparing = true
        isRefreshingPreview = false
        isImporting = false
        currentStep = .drop
        statusMessage = AppStrings.ViewModel.analyzingArchiveStatus
        appendLog(AppStrings.ViewModel.analyzingLog(droppedURL.path))

        let settingsSnapshot = settings

        analysisTask = Task {
            do {
                let context = try await coordinator.resolveAndPrepare(dropURL: droppedURL, settings: settingsSnapshot)
                guard !Task.isCancelled, prepareSequence == self.archivePrepareSequence else { return }
                applyPreparedContext(context)
                applyArchiveDatePrefill(from: context.overview)
                statusMessage = AppStrings.ViewModel.archiveReadyStatus
                appendLog(
                    AppStrings.ViewModel.archiveReadyLog(
                        totalTweets: context.overview.totalTweets,
                        threadsInRange: context.overview.threadsInDateRange
                    )
                )

                runPrerequisiteChecks()
            } catch is CancellationError {
                return
            } catch {
                guard prepareSequence == self.archivePrepareSequence else { return }
                setError(error.localizedDescription)
            }

            guard prepareSequence == self.archivePrepareSequence else { return }
            isPreparing = false
        }
    }

    func refreshPreview() {
        guard let archive = activeArchive else {
            return
        }

        previewRefreshSequence += 1
        let refreshSequence = previewRefreshSequence
        analysisTask?.cancel()
        // Show a dedicated busy state for Step 3 count recalculation.
        isRefreshingPreview = true
        isPreparing = true
        statusMessage = AppStrings.ViewModel.refreshingPreviewStatus

        let settingsSnapshot = settings
        analysisTask = Task {
            do {
                let context = try await coordinator.refresh(archive: archive, settings: settingsSnapshot)
                guard !Task.isCancelled, refreshSequence == self.previewRefreshSequence else { return }
                applyPreparedContext(context)
                statusMessage = AppStrings.ViewModel.previewRefreshedStatus
                appendLog(AppStrings.ViewModel.previewRefreshedLog)
            } catch is CancellationError {
                return
            } catch {
                guard refreshSequence == self.previewRefreshSequence else { return }
                setError(error.localizedDescription)
            }

            guard refreshSequence == self.previewRefreshSequence else { return }
            isRefreshingPreview = false
            isPreparing = false
        }
    }

    func runPrerequisiteChecks(refreshDayOneApp: Bool = false, refreshDayOneCLI: Bool = false) {
        checksTask?.cancel()
        isCheckingPrerequisites = true
        let requiredForDisplay = requiredChecks(refreshDayOneApp: false, refreshDayOneCLI: false).map { check in
            if (check.id == AppStrings.Prerequisites.dayOneAppID && refreshDayOneApp)
                || (check.id == AppStrings.Prerequisites.dayOneCLIID && refreshDayOneCLI) {
                return Self.checkingVariant(for: check)
            }
            return check
        }
        preflightChecks = requiredForDisplay + [Self.ollamaPlaceholderCheck()]
        let settingsSnapshot = settings

        checksTask = Task {
            let requiredChecks = self.requiredChecks(refreshDayOneApp: refreshDayOneApp, refreshDayOneCLI: refreshDayOneCLI)
            let ollamaCheck = await Self.evaluateOllamaPrerequisite(settings: settingsSnapshot)
            guard !Task.isCancelled else { return }
            self.preflightChecks = requiredChecks + [ollamaCheck]
            self.isCheckingPrerequisites = false
        }
    }

    func recheckDayOneApp() {
        runPrerequisiteChecks(refreshDayOneApp: true)
    }

    func recheckDayOneCLI() {
        runPrerequisiteChecks(refreshDayOneCLI: true)
    }

    func recheckOllama() {
        runPrerequisiteChecks()
    }

    func goToPrerequisitesStep() {
        currentStep = .prerequisites
        if !isCheckingPrerequisites {
            runPrerequisiteChecks()
        }
    }

    func goToSettingsStep() {
        guard canProceedFromPrerequisites else {
            setError(AppStrings.ViewModel.requiredPrereqError)
            return
        }
        // Step 2 already has the latest displayed prerequisite state; do not re-check on Continue.
        let ollamaReady = Self.ollamaTitlesEnabled(from: preflightChecks)
        settings.processTitlesWithLLM = ollamaReady
        currentStep = .settings
        appendLog(
            ollamaReady
                ? AppStrings.ViewModel.llmEnabledLog
                : AppStrings.ViewModel.llmDisabledLog
        )
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
        settings = ImportSettings()
        preflightChecks = Self.placeholderChecks()
        cachedDayOneAppCheck = nil
        cachedDayOneCLICheck = nil
        progress = Self.emptyProgressSnapshot(statusMessage: AppStrings.ViewModel.initialStatus)
        isRefreshingPreview = false
        statusMessage = AppStrings.ViewModel.resetFlowStatus
        currentStep = .drop
        appendLog(AppStrings.ViewModel.resetFlowLog)
    }

    func startImport() {
        guard !isImporting else { return }
        guard let archive = activeArchive else {
            setError(AppStrings.ViewModel.missingArchiveError)
            return
        }

        guard hasMetRequiredPrerequisites else {
            currentStep = .prerequisites
            setError(AppStrings.ViewModel.requiredPrereqStartImportError)
            return
        }

        isImporting = true
        currentStep = .progress
        statusMessage = AppStrings.ViewModel.preparingImportStatus
        appendLog(AppStrings.ViewModel.importStartedLog)

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
                    statusMessage = AppStrings.ViewModel.importCancelledStatus
                    appendLog(AppStrings.ViewModel.importCancelledLog(summary.attemptedThisRun))
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
        statusMessage = AppStrings.ViewModel.cancellingImportStatus
        appendLog(AppStrings.ViewModel.cancellationRequestedLog)
    }

    func resetSettingsToDefaults() {
        settings = ImportSettings()
        appendLog(AppStrings.ViewModel.settingsResetLog)
        runPrerequisiteChecks()
    }

    func clearLog() {
        logLines.removeAll()
    }

    private func applyPreparedContext(_ context: PreparedImportContext) {
        preparedContext = context
        activeArchive = context.archive
        overview = context.overview

        progress = Self.emptyProgressSnapshot(
            totalThreads: context.overview.threadsInDateRange,
            alreadyImported: context.overview.alreadyImported,
            statusMessage: AppStrings.ViewModel.readyStatus
        )
    }

    private static func emptyProgressSnapshot(
        totalThreads: Int = 0,
        alreadyImported: Int = 0,
        statusMessage: String
    ) -> ImportProgressSnapshot {
        ImportProgressSnapshot(
            totalThreads: totalThreads,
            alreadyImported: alreadyImported,
            importedThisRun: 0,
            skippedThisRun: 0,
            failedThisRun: 0,
            currentIndex: 0,
            currentTweetID: nil,
            currentCategory: nil,
            statusMessage: statusMessage
        )
    }

    private func applyArchiveDatePrefill(from overview: ArchiveOverview) {
        guard let earliest = overview.earliestTweetDate, let latest = overview.latestTweetDate else {
            return
        }
        settings.startDate = earliest
        settings.endDate = latest
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
        statusMessage = AppStrings.ViewModel.errorStatus
        appendLog(AppStrings.ViewModel.errorLog(message))
        isRefreshingPreview = false
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

    private static func placeholderChecks() -> [PrerequisiteCheck] {
        [dayOneAppPlaceholderCheck(), dayOneCLIPlaceholderCheck(), ollamaPlaceholderCheck()]
    }

    private func requiredChecks(refreshDayOneApp: Bool, refreshDayOneCLI: Bool) -> [PrerequisiteCheck] {
        // Cache Day One checks so Ollama-only retries do not keep probing local app/CLI state.
        let dayOneAppCheck: PrerequisiteCheck
        if !refreshDayOneApp, let cachedDayOneAppCheck {
            dayOneAppCheck = cachedDayOneAppCheck
        } else {
            dayOneAppCheck = Self.evaluateDayOneAppPrerequisite()
            cachedDayOneAppCheck = dayOneAppCheck
        }

        let dayOneCLICheck: PrerequisiteCheck
        if !refreshDayOneCLI, let cachedDayOneCLICheck {
            dayOneCLICheck = cachedDayOneCLICheck
        } else {
            dayOneCLICheck = Self.evaluateDayOneCLIPrerequisite()
            cachedDayOneCLICheck = dayOneCLICheck
        }

        return [dayOneAppCheck, dayOneCLICheck]
    }

    private static func dayOneAppPlaceholderCheck() -> PrerequisiteCheck {
        PrerequisiteCheck(
            id: AppStrings.Prerequisites.dayOneAppID,
            title: AppStrings.Prerequisites.dayOneAppTitle,
            details: AppStrings.Prerequisites.checkingApplications,
            isRequired: true,
            state: .checking
        )
    }

    private static func dayOneCLIPlaceholderCheck() -> PrerequisiteCheck {
        PrerequisiteCheck(
            id: AppStrings.Prerequisites.dayOneCLIID,
            title: AppStrings.Prerequisites.dayOneCLITitle,
            details: AppStrings.Prerequisites.checkingCLI,
            isRequired: true,
            state: .checking
        )
    }

    private static func ollamaPlaceholderCheck() -> PrerequisiteCheck {
        PrerequisiteCheck(
            id: AppStrings.Prerequisites.ollamaID,
            title: AppStrings.Prerequisites.ollamaTitle,
            details: AppStrings.Prerequisites.checkingOllama,
            isRequired: false,
            state: .checking
        )
    }

    private static func checkingVariant(for check: PrerequisiteCheck) -> PrerequisiteCheck {
        PrerequisiteCheck(
            id: check.id,
            title: check.title,
            details: check.details,
            isRequired: check.isRequired,
            state: .checking
        )
    }

    private static func evaluateDayOneAppPrerequisite() -> PrerequisiteCheck {
        let dayOnePaths = [
            AppStrings.ViewModel.dayOneAppPathPrimary,
            "\(NSHomeDirectory())\(AppStrings.ViewModel.dayOneAppPathUserSuffix)"
        ]

        let dayOnePath = dayOnePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        return PrerequisiteCheck(
            id: AppStrings.Prerequisites.dayOneAppID,
            title: AppStrings.Prerequisites.dayOneAppTitle,
            details: dayOnePath ?? AppStrings.Prerequisites.installDayOneHint,
            isRequired: true,
            state: dayOnePath == nil ? .failed : .passed
        )
    }

    private static func evaluateDayOneCLIPrerequisite() -> PrerequisiteCheck {
        let dayOneCLI = DayOneCLI()
        let dayOneExecutable = dayOneCLI.installedExecutablePath()
        return PrerequisiteCheck(
            id: AppStrings.Prerequisites.dayOneCLIID,
            title: AppStrings.Prerequisites.dayOneCLITitle,
            details: dayOneExecutable ?? AppStrings.Prerequisites.installDayOneCLIHints,
            isRequired: true,
            state: dayOneExecutable == nil ? .failed : .passed
        )
    }

    private static func evaluateOllamaPrerequisite(settings: ImportSettings) async -> PrerequisiteCheck {
        let ollamaProbe = await validateOllamaHelloResponse(
            apiURL: settings.ollamaAPIURL,
            modelName: settings.ollamaModelName
        )
        return PrerequisiteCheck(
            id: AppStrings.Prerequisites.ollamaID,
            title: AppStrings.Prerequisites.ollamaRunningTitle,
            details: ollamaProbe.details,
            isRequired: false,
            state: ollamaProbe.passed ? .passed : .warning
        )
    }

    private static func ollamaTitlesEnabled(from checks: [PrerequisiteCheck]) -> Bool {
        checks.first(where: { $0.id == AppStrings.Prerequisites.ollamaID })?.state == .passed
    }

    private static func validateOllamaHelloResponse(apiURL: String, modelName: String) async -> (passed: Bool, details: String) {
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            return (false, AppStrings.ViewModel.emptyModelError)
        }

        guard let url = normalizedOllamaGenerateURL(from: apiURL) else {
            return (false, AppStrings.ViewModel.invalidOllamaURLError)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": trimmedModel,
            "prompt": AppStrings.ViewModel.ollamaHelloPrompt,
            "stream": false
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return (false, AppStrings.ViewModel.failedEncodeOllamaBodyError)
        }
        request.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, AppStrings.ViewModel.missingHTTPResponseError)
            }

            guard (200 ... 299).contains(http.statusCode) else {
                let raw = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let preview = raw.prefix(140)
                let suffix = raw.count > 140 ? "..." : ""
                return (false, AppStrings.ViewModel.ollamaHTTPError(statusCode: http.statusCode, preview: String(preview), suffix: suffix))
            }

            guard
                let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                let responseText = object["response"] as? String
            else {
                return (false, AppStrings.ViewModel.unexpectedOllamaResponseError)
            }

            let normalized = responseText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized == AppStrings.ViewModel.ollamaExpectedHello else {
                return (false, AppStrings.ViewModel.ollamaUnexpectedAnswer(normalized))
            }

            return (true, AppStrings.ViewModel.ollamaHelloSuccess)
        } catch {
            return (false, AppStrings.ViewModel.ollamaConnectionFailed(error.localizedDescription))
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
