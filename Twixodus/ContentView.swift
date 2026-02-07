import SwiftUI
import UniformTypeIdentifiers

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
        .alert("Import Error", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.settings.processTitlesWithLLM) { _, _ in
            if viewModel.currentStep == .prerequisites {
                viewModel.runPrerequisiteChecks()
            }
        }
        .onChange(of: viewModel.settings.skipAlreadyImported) { _, _ in
            if viewModel.hasArchive && !viewModel.isPreparing && !viewModel.isImporting {
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
                Button("Continue") {
                    viewModel.goToPrerequisitesStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceedFromDrop)

            case .prerequisites:
                Button("Back") {
                    viewModel.currentStep = .drop
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Continue") {
                    viewModel.goToSettingsStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceedFromPrerequisites)

            case .settings:
                Button("Back") {
                    viewModel.goBackFromSettings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(viewModel.isImporting ? "Importing..." : "Start Import") {
                    viewModel.startImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canImport)

            case .progress:
                Button("Back") {
                    viewModel.goBackFromProgress()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isImporting)

                Spacer()

                Button("Cancel Import") {
                    viewModel.cancelImport()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isImporting)

            case .done:
                Spacer()
                Button("Import Another Archive") {
                    viewModel.restartWithNewArchive()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var dropPage: some View {
        VStack(spacing: 12) {
            Text("Step 1: Drop Archive")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isPreparing {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Analyzing archive")
                        .font(.headline)
                    Text("Please wait while archive stats are generated.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackground)
            } else if let overview = viewModel.overview {
                VStack(spacing: 14) {
                    metricRow("Tweets", value: "\(overview.totalTweets)")
                    metricRow("Threads", value: "\(overview.threadsInDateRange)")
                    metricRow("Date Range", value: viewModel.dateRangeText)
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
                    Text("Drag and drop here")
                        .font(.title3.weight(.semibold))
                    Text("Twitter archive folder or .zip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Choose Archive") {
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
            Text("Step 2: Pre-requisites")
                .font(.headline)

            Text("Please create a Day One journal for tweets and for replies before importing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(viewModel.preflightChecks) { check in
                    prerequisiteRow(check)
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
                Text("Step 3: Import Settings")
                    .font(.headline)

                if let username = viewModel.detectedUsername {
                    Text("Archive user: @\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Tweet Journal")
                            .foregroundStyle(.secondary)
                        TextField("Tweets", text: $viewModel.settings.journalName)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text("Import Replies")
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $viewModel.settings.includeReplies)
                            .labelsHidden()
                    }

                    if viewModel.settings.includeReplies {
                        GridRow {
                            Text("Reply Journal")
                                .foregroundStyle(.secondary)
                            TextField("Twitter Replies", text: $viewModel.settings.replyJournalName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    GridRow {
                        Text("Ignore Retweets")
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $viewModel.settings.ignoreRetweets)
                            .labelsHidden()
                    }

                    GridRow {
                        Text("Skip Already Imported")
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $viewModel.settings.skipAlreadyImported)
                            .labelsHidden()
                    }

                    GridRow {
                        Text("Date Range")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            DatePicker("", selection: $viewModel.settings.startDate, displayedComponents: .date)
                                .labelsHidden()
                            Text("-")
                            DatePicker("", selection: $viewModel.settings.endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    GridRow {
                        Text("LLM Titles")
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $viewModel.settings.processTitlesWithLLM)
                            .labelsHidden()
                    }
                }

                if viewModel.settings.processTitlesWithLLM {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ollama API URL", text: $viewModel.settings.ollamaAPIURL)
                            .textFieldStyle(.roundedBorder)
                        TextField("Ollama model", text: $viewModel.settings.ollamaModelName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Prompt", text: $viewModel.settings.ollamaPrompt, axis: .vertical)
                            .lineLimit(2 ... 4)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Button("Refresh Preview") {
                        viewModel.refreshPreview()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasArchive || viewModel.isPreparing || viewModel.isImporting)

                    Button("Defaults") {
                        viewModel.resetSettingsToDefaults()
                    }
                    .buttonStyle(.bordered)
                }

                if let overview = viewModel.overview {
                    HStack(spacing: 10) {
                        metricMini("Threads", value: "\(overview.threadsInDateRange)")
                        metricMini("Pending", value: "\(overview.pendingToImport)")
                        metricMini("Imported", value: viewModel.settings.skipAlreadyImported ? "\(overview.alreadyImported)" : "Off")
                    }
                }
            }
            .padding(16)
        }
    }

    private var progressPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 4: Import Progress")
                .font(.headline)

            HStack {
                Text("Progress")
                Spacer()
                Text("\(Int(viewModel.progress.fraction * 100))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: viewModel.progress.fraction)
                .progressViewStyle(.linear)

            HStack(spacing: 10) {
                metricMini("Imported", value: "\(viewModel.progress.importedThisRun)")
                metricMini("Skipped", value: "\(viewModel.progress.skippedThisRun)")
                metricMini("Failed", value: "\(viewModel.progress.failedThisRun)")
                metricMini("Total", value: "\(viewModel.progress.totalThreads)")
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
            Text("Import Finished")
                .font(.headline)

            if let summary = viewModel.lastRunSummary {
                HStack(spacing: 10) {
                    metricMini("Imported", value: "\(summary.importedThisRun)")
                    metricMini("Skipped", value: "\(summary.skippedThisRun)")
                    metricMini("Failed", value: "\(summary.failedThisRun)")
                }
            }

            Text("You can now review imported entries in Day One.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
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
                        Text("Optional")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.12)))
                    }
                }

                Text(check.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if check.id == "ollama-localhost" && check.state != .passed {
                    Button(viewModel.isCheckingPrerequisites ? "Checking..." : "Re-check") {
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
