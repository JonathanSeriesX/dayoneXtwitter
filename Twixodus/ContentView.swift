import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var viewModel = ImportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            stepsRail
            Divider()
            pageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            navigationBar
        }
        .frame(width: 900, height: 600)
        .containerBackground(.regularMaterial, for: .window)
        .alert(AppStrings.Alert.importErrorTitle, isPresented: $viewModel.isShowingError) {
            Button(AppStrings.Alert.okButton, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.settings.startDate) { _, _ in
            if viewModel.currentStep == .settings && viewModel.hasArchive && !viewModel.isImporting {
                viewModel.refreshPreview()
            }
        }
        .onChange(of: viewModel.settings.endDate) { _, _ in
            if viewModel.currentStep == .settings && viewModel.hasArchive && !viewModel.isImporting {
                viewModel.refreshPreview()
            }
        }
    }

    private var stepsRail: some View {
        HStack(spacing: 8) {
            ForEach(WizardStep.allCases) { step in
                stepChip(step)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var pageBody: some View {
        switch viewModel.currentStep {
        case .drop:
            dropPage
        case .prerequisites:
            prerequisitesPage
        case .settings:
            settingsPage
        case .progress:
            progressPage
        case .done:
            donePage
        }
    }

    private var navigationBar: some View {
        HStack {
            switch viewModel.currentStep {
            case .drop:
                Spacer()
                Button(AppStrings.Navigation.continueButton) {
                    viewModel.goToPrerequisitesStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceedFromDrop)

            case .prerequisites:
                Button(AppStrings.Navigation.backButton) {
                    viewModel.currentStep = .drop
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(AppStrings.Navigation.continueButton) {
                    viewModel.goToSettingsStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceedFromPrerequisites)

            case .settings:
                Button(AppStrings.Navigation.backButton) {
                    viewModel.goBackFromSettings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(viewModel.isImporting ? AppStrings.Navigation.importingButton : AppStrings.Navigation.startImportButton) {
                    viewModel.startImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canImport)

            case .progress:
                Button(AppStrings.Navigation.backButton) {
                    viewModel.goBackFromProgress()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isImporting)

                Spacer()

                Button(AppStrings.Navigation.cancelImportButton) {
                    viewModel.cancelImport()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isImporting)

            case .done:
                Spacer()
                Button(AppStrings.Navigation.closeButton) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var dropPage: some View {
        VStack(spacing: 12) {
            Text(AppStrings.DropStep.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isPreparing {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                    Text(AppStrings.DropStep.analyzingTitle)
                        .font(.headline)
                    Text(AppStrings.DropStep.analyzingDetails)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackground)
            } else if let overview = viewModel.overview {
                VStack(spacing: 14) {
                    metricRow(AppStrings.DropStep.tweetsLabel, value: "\(overview.totalTweets)")
                    metricRow(AppStrings.DropStep.threadsLabel, value: "\(overview.threadsInDateRange)")
                    metricRow(AppStrings.DropStep.dateRangeLabel, value: viewModel.dateRangeText)
                }
                .frame(maxWidth: 500)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackground)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 52))
                        .symbolRenderingMode(.hierarchical)
                    Text(AppStrings.DropStep.dragTitle)
                        .font(.title3.weight(.semibold))
                    Text(AppStrings.DropStep.dragSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(AppStrings.DropStep.chooseArchiveButton) {
                        viewModel.chooseArchive()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(
                                lineWidth: viewModel.isDropTargeted ? 2 : 1.2,
                                dash: [9, 7]
                            )
                        )
                        .foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : .secondary.opacity(0.65))
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
                    viewModel.handleDrop(providers: providers)
                }
            }
        }
        .padding(16)
    }

    private var prerequisitesPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.PrerequisitesStep.title)
                .font(.headline)

            Text(AppStrings.PrerequisitesStep.intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(viewModel.preflightChecks) { check in
                    prerequisiteRow(check)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(AppStrings.PrerequisitesStep.ollamaURLLabel)
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.PrerequisitesStep.ollamaURLPlaceholder, text: $viewModel.settings.ollamaAPIURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(AppStrings.PrerequisitesStep.modelLabel)
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.PrerequisitesStep.modelPlaceholder, text: $viewModel.settings.ollamaModelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            viewModel.runPrerequisiteChecks()
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.SettingsStep.title)
                    .font(.headline)

                if let username = viewModel.detectedUsername {
                    Text("\(AppStrings.SettingsStep.archiveUserPrefix)\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(AppStrings.SettingsStep.tweetJournalLabel)
                            .foregroundStyle(.secondary)
                        TextField(AppStrings.SettingsStep.tweetJournalPlaceholder, text: $viewModel.settings.journalName)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text(AppStrings.SettingsStep.importRepliesLabel)
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $viewModel.settings.includeReplies)
                            .labelsHidden()
                    }

                    if viewModel.settings.includeReplies {
                        GridRow {
                            Text(AppStrings.SettingsStep.replyJournalLabel)
                                .foregroundStyle(.secondary)
                            TextField(AppStrings.SettingsStep.replyJournalPlaceholder, text: $viewModel.settings.replyJournalName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    GridRow {
                        Text(AppStrings.SettingsStep.ignoreRetweetsLabel)
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $viewModel.settings.ignoreRetweets)
                            .labelsHidden()
                    }

                    GridRow {
                        Text(AppStrings.SettingsStep.dateRangeLabel)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            DatePicker("", selection: $viewModel.settings.startDate, displayedComponents: .date)
                                .labelsHidden()
                            Text(AppStrings.SettingsStep.dateRangeSeparator)
                            DatePicker("", selection: $viewModel.settings.endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }

                if let overview = viewModel.overview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.SettingsStep.withinDateRangeLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        metricMini(AppStrings.SettingsStep.withinDateRangeThreadsLabel, value: "\(overview.threadsInDateRange)")
                    }
                }
            }
            .padding(16)
        }
    }

    private var progressPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.ProgressStep.title)
                .font(.headline)

            HStack {
                Text(AppStrings.ProgressStep.progressLabel)
                Spacer()
                Text("\(Int(viewModel.progress.fraction * 100))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: viewModel.progress.fraction)
                .progressViewStyle(.linear)

            HStack(spacing: 10) {
                metricMini(AppStrings.ProgressStep.importedLabel, value: "\(viewModel.progress.importedThisRun)")
                metricMini(AppStrings.ProgressStep.skippedLabel, value: "\(viewModel.progress.skippedThisRun)")
                metricMini(AppStrings.ProgressStep.failedLabel, value: "\(viewModel.progress.failedThisRun)")
                metricMini(AppStrings.ProgressStep.totalLabel, value: "\(viewModel.progress.totalThreads)")
            }

            Text(viewModel.progress.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(cardBackground)
        }
        .padding(16)
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.DoneStep.title)
                .font(.headline)

            if let summary = viewModel.lastRunSummary {
                HStack(spacing: 10) {
                    metricMini(AppStrings.ProgressStep.importedLabel, value: "\(summary.importedThisRun)")
                    metricMini(AppStrings.ProgressStep.skippedLabel, value: "\(summary.skippedThisRun)")
                    metricMini(AppStrings.ProgressStep.failedLabel, value: "\(summary.failedThisRun)")
                }
            }

            Text(AppStrings.DoneStep.details)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.DoneStep.donationTitle)
                    .font(.subheadline.weight(.semibold))
                Text(AppStrings.DoneStep.donationDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    if let url = URL(string: AppStrings.DoneStep.buyMeCoffeeURL) {
                        Link(AppStrings.DoneStep.buyMeCoffeeLabel, destination: url)
                    }

                    Text("\(AppStrings.DoneStep.usdtLabel) \(AppStrings.DoneStep.usdtAddress)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Text(AppStrings.DoneStep.logTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(cardBackground)
        }
        .padding(16)
    }

    private func stepChip(_ step: WizardStep) -> some View {
        let isCurrent = step == viewModel.currentStep
        let isDone = step.rawValue < viewModel.currentStep.rawValue

        return HStack(spacing: 6) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 18, height: 18)
                .overlay {
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(step.shortLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isCurrent ? .white : .primary)
                    }
                }
            Text(step.title)
                .font(.caption)
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        )
    }

    private func prerequisiteRow(_ check: PrerequisiteCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.state.symbolName)
                .foregroundStyle(prereqColor(check.state))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(check.title)
                        .font(.subheadline.weight(.semibold))

                    if !check.isRequired {
                        Text(AppStrings.PrerequisitesStep.optionalBadge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.12)))
                    }
                }

                Text(check.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if check.id == AppStrings.Prerequisites.ollamaID && check.state != .passed {
                    Button(viewModel.isCheckingPrerequisites ? AppStrings.PrerequisitesStep.checkingButton : AppStrings.PrerequisitesStep.recheckButton) {
                        viewModel.runPrerequisiteChecks()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isCheckingPrerequisites)
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func prereqColor(_ state: PrerequisiteState) -> Color {
        switch state {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        case .checking:
            return .secondary
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }

    private func metricMini(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.07))
    }
}
