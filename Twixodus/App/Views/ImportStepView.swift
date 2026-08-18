// Step 3 of the flow: the import run — progress, a live log of what's being
// imported, and pause/resume/cancel.

import SwiftUI

struct ImportStepView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                progressHeader
            }
            .padding(20)

            Divider()

            logView

            Divider()

            HStack {
                Button {
                    model.togglePause()
                } label: {
                    Label(model.isPaused ? "Resume" : "Pause",
                          systemImage: model.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 80)
                }
                .primaryActionButtonStyle()

                Button("Cancel", role: .cancel) { model.cancelImport() }
                    .secondaryActionButtonStyle()

                Spacer()

                if model.isPaused {
                    Label("Paused — safe to leave it like this, the ledger remembers every imported thread",
                          systemImage: "pause.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    /// The engine's denominator shrinks when a pending thread turns out not to
    /// produce an entry (skipped by configuration, or Day One rejected it) —
    /// it can even reach zero mid-run, so "Preparing…" and the percentage key
    /// off progressStarted, never off the denominator alone.
    private var headline: String {
        if !model.progressStarted { return "Preparing…" }
        if model.totalPending == 0 { return "Imported \(model.importedCount)" }
        return "Imported \(model.importedCount) of \(model.totalPending)"
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.default, value: model.importedCount)
                Spacer()
                if model.progressStarted, model.totalPending > 0 {
                    Text("\(Int((Double(model.importedCount) / Double(model.totalPending) * 100).rounded()))%")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // With nothing (left) to import, show the bar as done, not empty.
            ProgressView(
                value: model.progressStarted && model.totalPending == 0
                    ? 1 : Double(model.importedCount),
                total: model.progressStarted && model.totalPending == 0
                    ? 1 : Double(max(model.totalPending, 1))
            )
            .progressViewStyle(.linear)

            HStack {
                Text(model.activity)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.logLines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(12)
            }
            .background(.quaternary.opacity(0.3))
            .onChange(of: model.logLines.last?.id) { _, lastId in
                if let lastId {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    private func color(for kind: ImportLogKind) -> Color {
        switch kind {
        case .info: return .secondary
        case .thread: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
