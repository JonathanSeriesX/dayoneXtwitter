import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ImportViewModel()

    var body: some View {
        VStack(spacing: 18) {
            header
            stepsRail
            pageCard
            navigationBar
        }
        .padding(22)
        .frame(minWidth: 980, minHeight: 820)
        .alert("Import Error", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.settings.processTitlesWithLLM) { _, _ in
            viewModel.runPrerequisiteChecks()
        }
        .onChange(of: viewModel.settings.skipAlreadyImported) { _, _ in
            if viewModel.hasArchive && !viewModel.isPreparing && !viewModel.isImporting {
                viewModel.refreshPreview()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Twixodus")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(viewModel.currentStep.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let overview = viewModel.overview {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(overview.archivePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    if let username = viewModel.detectedUsername {
                        Text("@\(username)")
                            .font(.headline.monospaced())
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private var stepsRail: some View {
        HStack(spacing: 10) {
            ForEach(WizardStep.allCases) { step in
                stepBadge(for: step)
            }
        }
    }

    private var pageCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(22)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
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

            case .progress:
                Button("Back") {
                    viewModel.goBackFromProgress()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isImporting)
                Spacer()

            case .done:
                Spacer()
                Button("Import Another Archive") {
                    viewModel.restartWithNewArchive()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dropPage: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text("Step 1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Drop your Twitter archive")
                    .font(.title.weight(.semibold))
                Text("Drop a folder or zip file. Zip archives are extracted into a folder named after the archive in the same parent folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 60))
                    .symbolRenderingMode(.hierarchical)
                Text("Drag & Drop Here")
                    .font(.title2.weight(.semibold))
                Button("Choose Archive") {
                    viewModel.chooseArchive()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 330)
            .background(dropZoneBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: viewModel.isDropTargeted ? 2.5 : 1.5,
                            dash: [12, 9],
                            dashPhase: viewModel.isDropTargeted ? 16 : 0
                        )
                    )
                    .foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : .secondary.opacity(0.7))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isDropTargeted)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
                viewModel.handleDrop(providers: providers)
            }

            if let overview = viewModel.overview {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    metricCard("Tweets", value: "\(overview.totalTweets)")
                    metricCard("Threads", value: "\(overview.threadsInDateRange)")
                    metricCard("Already Imported", value: viewModel.settings.skipAlreadyImported ? "\(overview.alreadyImported)" : "Off")
                    metricCard("Pending", value: "\(overview.pendingToImport)")
                }
            }
        }
    }

    private var prerequisitesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Prerequisites")
                .font(.title.weight(.semibold))

            Text("Confirm these checks before importing. Required items must be green.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(viewModel.preflightChecks) { check in
                    prerequisiteRow(check)
                }
            }

            HStack(spacing: 10) {
                Button(viewModel.isCheckingPrerequisites ? "Checking..." : "Re-check") {
                    viewModel.runPrerequisiteChecks()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCheckingPrerequisites)

                if viewModel.hasMetRequiredPrerequisites {
                    Label("Required checks passed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Label("Required checks incomplete", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Import settings")
                .font(.title.weight(.semibold))

            if let username = viewModel.detectedUsername {
                Label("Archive username: @\(username)", systemImage: "person.text.rectangle")
                    .font(.headline)
            } else {
                Label("Archive username not found in data/account.js", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if let displayName = viewModel.detectedDisplayName {
                Text(displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Grid(horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    label("Tweet Journal")
                    TextField("Tweets", text: $viewModel.settings.journalName)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    label("Replies")
                    Toggle("Import replies", isOn: $viewModel.settings.includeReplies)
                }

                if viewModel.settings.includeReplies {
                    GridRow {
                        label("Reply Journal")
                        TextField("Twitter Replies", text: $viewModel.settings.replyJournalName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                GridRow {
                    label("Ignore Retweets")
                    Toggle("Skip retweets", isOn: $viewModel.settings.ignoreRetweets)
                }

                GridRow {
                    label("Duplicate Guard")
                    Toggle("Skip entries listed in processed_tweets.txt", isOn: $viewModel.settings.skipAlreadyImported)
                }

                GridRow {
                    label("Date Range")
                    HStack {
                        DatePicker("Start", selection: $viewModel.settings.startDate, displayedComponents: .date)
                        DatePicker("End", selection: $viewModel.settings.endDate, displayedComponents: .date)
                    }
                }

                GridRow {
                    label("LLM Titles")
                    Toggle("Generate thread titles with Ollama", isOn: $viewModel.settings.processTitlesWithLLM)
                }
            }

            if viewModel.settings.processTitlesWithLLM {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Ollama API URL", text: $viewModel.settings.ollamaAPIURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Ollama model", text: $viewModel.settings.ollamaModelName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Prompt", text: $viewModel.settings.ollamaPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2 ... 5)
                }
            }

            HStack(spacing: 10) {
                Button("Refresh Preview") {
                    viewModel.refreshPreview()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasArchive || viewModel.isPreparing || viewModel.isImporting)

                Button("Defaults") {
                    viewModel.resetSettingsToDefaults()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(viewModel.isImporting ? "Importing..." : "Start Import") {
                    viewModel.startImport()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canImport)
            }

            if let overview = viewModel.overview {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    metricCard("Date Span", value: viewModel.dateRangeText)
                    metricCard("Threads", value: "\(overview.threadsInDateRange)")
                    metricCard("Already Imported", value: viewModel.settings.skipAlreadyImported ? "\(overview.alreadyImported)" : "Off")
                    metricCard("Pending", value: "\(overview.pendingToImport)")
                }
            }
        }
    }

    private var progressPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 4")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Import progress")
                .font(.title.weight(.semibold))

            HStack {
                Text("Progress")
                    .font(.headline)
                Spacer()
                Text("\(Int(viewModel.progress.fraction * 100))%")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: viewModel.progress.fraction)
                .progressViewStyle(.linear)

            HStack(spacing: 14) {
                counter(label: "Imported", value: viewModel.progress.importedThisRun)
                counter(label: "Skipped", value: viewModel.progress.skippedThisRun)
                counter(label: "Failed", value: viewModel.progress.failedThisRun)
                counter(label: "Total", value: viewModel.progress.totalThreads)
            }

            if let currentID = viewModel.progress.currentTweetID {
                Text("Current tweet: \(currentID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel Import") {
                    viewModel.cancelImport()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isImporting)

                Spacer()

                Text(viewModel.progress.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            logPanel
        }
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Step 5")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Import finished")
                .font(.title.weight(.semibold))

            if let summary = viewModel.lastRunSummary {
                HStack(spacing: 14) {
                    metricCard("Imported", value: "\(summary.importedThisRun)")
                    metricCard("Skipped", value: "\(summary.skippedThisRun)")
                    metricCard("Failed", value: "\(summary.failedThisRun)")
                    metricCard("Already Imported", value: "\(summary.alreadyImported)")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("If this app saved you time, support the project:")
                    .font(.headline)

                Link("Buy me a coffee", destination: URL(string: "https://coff.ee/jonathunky")!)
                Text("USDT TRC20: TKa6wmqpLvMQwacU1wnPgFWZHFaDRV9jFs")
                    .textSelection(.enabled)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )

            Text("You can now open Day One and browse imported entries.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.clearLog()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 150, maxHeight: 220)
        }
    }

    private func stepBadge(for step: WizardStep) -> some View {
        let isCurrent = viewModel.currentStep == step
        let isCompleted = step.rawValue < viewModel.currentStep.rawValue

        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.18))
                Text(step.shortLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isCurrent ? Color.white : .primary)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.caption.weight(.semibold))
                if isCompleted {
                    Text("Done")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        )
    }

    private func prerequisiteRow(_ check: PrerequisiteCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.state.symbolName)
                .font(.title3)
                .foregroundStyle(prereqColor(for: check.state))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(check.title)
                        .font(.headline)
                    if check.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                }

                Text(check.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(check.state.statusLabel)
                    .font(.caption)
                    .foregroundStyle(prereqColor(for: check.state))
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func prereqColor(for state: PrerequisiteState) -> Color {
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

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 140, alignment: .leading)
    }

    private func counter(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline.monospacedDigit())
        }
    }

    private var dropZoneBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.secondary.opacity(0.06))
    }
}
