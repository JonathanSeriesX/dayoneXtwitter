// Step 2 of the flow: everything config.py used to be, as a form. The
// archive summary sits on top so the user can sanity-check what was loaded.

import SwiftUI

struct ConfigureStepView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                archiveSection
                journalsSection
                accountSection
                dateRangeSection
                optionsSection
                llmSection
                dayOneSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Back") { model.startOver() }
                    .secondaryActionButtonStyle()
                Spacer()
                if model.dayOneBinary == nil {
                    Label("Install the Day One CLI to start", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Button("Start Import") { model.startImport() }
                    .primaryActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.dayOneBinary == nil || journalNameInvalid)
            }
            .padding(14)
        }
        .onAppear {
            model.refreshDayOneBinary()
            model.refreshAlreadyImportedCount()
        }
    }

    private var journalNameInvalid: Bool {
        settings.journalName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Sections

    @ViewBuilder
    private var archiveSection: some View {
        if let archive = model.archive {
            Section("Archive") {
                LabeledContent("Account") {
                    Text(archive.archiveUsername.map { "@\($0)" } ?? "unknown")
                }
                LabeledContent("Tweets") {
                    Text("\(archive.tweets.count), in \(archive.threads.count) threads")
                }
                if let range = archive.threadDateRange {
                    LabeledContent("Covers") {
                        Text("\(Self.dayFormatter.string(from: range.lowerBound)) — \(Self.dayFormatter.string(from: range.upperBound))")
                    }
                }
                if archive.adoptedOrphans > 0 {
                    LabeledContent("Repaired") {
                        Text("\(archive.adoptedOrphans) self-replies whose parent tweet is gone")
                    }
                }
                if model.alreadyImportedCount > 0 {
                    LabeledContent("Already imported") {
                        Text("\(model.alreadyImportedCount) threads (from previous runs — they'll be skipped)")
                    }
                }
                ForEach(archive.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
    }

    private var journalsSection: some View {
        Section("Journals") {
            TextField("Journal for tweets", text: $settings.journalName)
            Toggle("Import replies too", isOn: $settings.importReplies)
            if settings.importReplies {
                TextField("Journal for replies", text: $settings.replyJournalName)
            }
            Text("Create these journals in Day One first — the CLI won't create them for you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Toggle("My account still exists", isOn: $settings.accountStillExists)
            if settings.accountStillExists {
                TextField("Current username", text: $settings.currentUsername, prompt: Text("username"))
                Text("Used to build links back to your tweets. Turn the toggle off if you've deleted your account forever — entries then get no twitter.com links.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateRangeSection: some View {
        Section("Date range") {
            if let covered = model.lastCoveredDate {
                HStack {
                    Label(
                        "Previous imports covered everything through \(Self.dayFormatter.string(from: covered))",
                        systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Button("Import Only Newer Tweets") { model.continueFromLastImport() }
                        .secondaryActionButtonStyle()
                }
            }
            DatePicker("From", selection: $settings.startDate, displayedComponents: .date)
            DatePicker("Until", selection: $settings.endDate, displayedComponents: .date)
            Text("Only threads that started between these days (inclusive) are imported. Threads that started earlier but gained tweets inside the range are re-imported in full — you'll get a reminder to delete the older, shorter copies.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            Toggle("Import in random order (useful for previewing results)", isOn: $settings.shuffleMode)
            Toggle("Skip retweets", isOn: $settings.ignoreRetweets)
            Toggle("End entries with “Sent from <client>”", isOn: $settings.showTweetSource)
            Toggle("Point tweet links at xcancel.com instead of twitter.com", isOn: $settings.useXcancelLinks)
            Toggle("Limit threads per run", isOn: $settings.limitThreads)
            if settings.limitThreads {
                TextField("Max threads", value: $settings.maxThreadsToProcess, format: .number)
            }
        }
    }

    private var llmSection: some View {
        Section {
            Toggle("Title entries with a local LLM", isOn: $settings.llmTitlesEnabled)
            if settings.llmTitlesEnabled {
                Toggle("Also title standalone tweets (slower)", isOn: $settings.llmTitlesForSingleTweets)
                TextField("Ollama server", text: $settings.ollamaHost)
                TextField("Model", text: $settings.ollamaModelName)
                Stepper(value: $settings.llmMaxImages, in: 0...26) {
                    LabeledContent("Images shown to the model", value: "\(settings.llmMaxImages)")
                }
                DisclosureGroup("Title prompt") {
                    TextEditor(text: $settings.ollamaTitlePrompt)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 140)
                    Button("Reset to default") {
                        settings.ollamaTitlePrompt = ImportConfig.defaultTitlePrompt
                    }
                    .secondaryActionButtonStyle()
                }
            }
        } header: {
            Text("AI titles")
        } footer: {
            if settings.llmTitlesEnabled {
                Text("Needs [Ollama](https://ollama.com) running with the model pulled, e.g. `ollama pull \(settings.ollamaModelName)`. Titles come out like “Expressed frustration at airport security”; when the model isn't sure, the plain category title is kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dayOneSection: some View {
        Section("Day One") {
            if model.dayOneBinary == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label("The Day One CLI isn't installed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Install it from Day One's own guide, then come back — this screen re-checks automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Open the install instructions",
                         destination: URL(string: "https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/")!)
                        .font(.footnote)
                }
            }
            Text("Keep the Day One app running during the import: the app is what moves staged media into the entries.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
