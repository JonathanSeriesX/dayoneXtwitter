import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ImportViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                dropZone
                metricsGrid
                importPanel
                settingsPanel
                logPanel
            }
            .padding(20)
        }
        .background(backgroundView)
        .alert("Import Error", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .frame(minWidth: 980, minHeight: 820)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Twixodus")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                Text("Import your Twitter/X archive into Day One with native macOS tooling")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button("Choose Archive") {
                    viewModel.chooseArchive()
                }
                .buttonStyle(.borderedProminent)

                if viewModel.isPreparing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.primary)

            Text("Drop a Twitter archive folder or zip")
                .font(.title3.weight(.semibold))

            Text("Zip files are extracted into a folder named after the archive (in the same parent folder). You can also drop an already extracted archive folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)

            if let overview = viewModel.overview {
                Text(overview.archivePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .background(dropZoneBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(
                        lineWidth: viewModel.isDropTargeted ? 3 : 2,
                        dash: [10, 8],
                        dashPhase: viewModel.isDropTargeted ? 12 : 0
                    )
                )
                .foregroundStyle(viewModel.isDropTargeted ? .white.opacity(0.75) : .white.opacity(0.45))
                .animation(.easeInOut(duration: 0.2), value: viewModel.isDropTargeted)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            metricCard("Tweets", value: metricValue(overview: viewModel.overview?.totalTweets))
            metricCard("Threads", value: metricValue(overview: viewModel.overview?.threadsInDateRange))
            metricCard("Already Imported", value: metricValue(overview: viewModel.overview?.alreadyImported))
            metricCard("Pending", value: metricValue(overview: viewModel.overview?.pendingToImport))
            metricCard("Date Span", value: viewModel.dateRangeText)
        }
    }

    private var importPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Import")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(Int(viewModel.progress.fraction * 100))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: viewModel.progress.fraction)
                .progressViewStyle(.linear)
                .tint(LinearGradient(
                    colors: [Color.cyan, Color.blue, Color.indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                ))

            HStack(spacing: 18) {
                counter(label: "Imported", value: viewModel.progress.importedThisRun)
                counter(label: "Skipped", value: viewModel.progress.skippedThisRun)
                counter(label: "Failed", value: viewModel.progress.failedThisRun)
                Spacer()
                counter(label: "Completed", value: viewModel.progress.completedTotal)
                counter(label: "Total", value: viewModel.progress.totalThreads)
            }

            HStack(spacing: 10) {
                Button("Refresh Preview") {
                    viewModel.refreshPreview()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasArchive || viewModel.isPreparing || viewModel.isImporting)

                Button(viewModel.isImporting ? "Importing..." : "Import to Day One") {
                    viewModel.startImport()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canImport)

                Button("Cancel") {
                    viewModel.cancelImport()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isImporting)
            }

            if let currentTweetID = viewModel.progress.currentTweetID {
                Text("Current: \(currentTweetID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(panelMaterial)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Defaults") {
                    viewModel.resetSettingsToDefaults()
                }
                .buttonStyle(.bordered)
            }

            Grid(horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    label("Tweet Journal")
                    TextField("Tweets", text: $viewModel.settings.journalName)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    label("Current Username")
                    TextField("JonathanSeriesX", text: $viewModel.settings.currentUsername)
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

        }
        .padding(18)
        .background(panelMaterial)
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.title3.weight(.semibold))
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
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 240)
            .padding(10)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .background(panelMaterial)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(panelMaterial)
    }

    private func metricValue(overview: Int?) -> String {
        guard let value = overview else { return "-" }
        return "\(value)"
    }

    private var panelMaterial: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 12)
    }

    private var dropZoneBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.23, blue: 0.34),
                        Color(red: 0.14, green: 0.19, blue: 0.30),
                        Color(red: 0.10, green: 0.12, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(viewModel.isDropTargeted ? 0.07 : 0.02))
            }
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 12)
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.17),
                    Color(red: 0.08, green: 0.07, blue: 0.13),
                    Color(red: 0.10, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 420)
                .blur(radius: 18)
                .offset(x: -260, y: -260)

            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 360)
                .blur(radius: 26)
                .offset(x: 300, y: 260)
        }
    }
}

#Preview {
    ContentView()
}
