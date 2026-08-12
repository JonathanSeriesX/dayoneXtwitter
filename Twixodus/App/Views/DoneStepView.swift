// Step 4 of the flow: the wrap-up — how the run went, and the reminder to
// delete older copies of re-imported threads, if there were any.

import SwiftUI
import AppKit

struct DoneStepView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                summaryHeader
            }
            .padding(24)

            if let report = model.runResult?.reimportReport {
                Divider()
                reportView(report)
            } else {
                Spacer()
            }

            Divider()

            HStack {
                Button("Back to Settings") { model.backToConfigure() }
                    .secondaryActionButtonStyle()
                Spacer()
                Button("Import Another Archive") { model.startOver() }
                    .primaryActionButtonStyle()
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        let result = model.runResult

        Image(systemName: symbolName)
            .font(.system(size: 42))
            .foregroundStyle(result?.wasCancelled == true ? AnyShapeStyle(.orange) : AnyShapeStyle(.green))

        Text(headline)
            .font(.title2.weight(.semibold))

        if let result {
            VStack(spacing: 3) {
                if result.skippedAlreadyImported > 0 {
                    Text("\(result.skippedAlreadyImported) threads were already in Day One from earlier runs and were skipped.")
                }
                if result.stoppedAtLimit {
                    Text("Stopped at the per-run thread limit — press Import again to continue where it left off.")
                }
                if result.wasCancelled {
                    Text("Cancelled — everything imported so far is recorded, so the next run picks up where this one stopped.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var symbolName: String {
        if model.runResult?.wasCancelled == true { return "stop.circle" }
        return "checkmark.circle"
    }

    private var headline: String {
        guard let result = model.runResult else { return "Done" }
        if result.importedCount == 0 && result.totalPending == 0 {
            return "Nothing new to import"
        }
        return "Imported \(result.importedCount) entr\(result.importedCount == 1 ? "y" : "ies")"
    }

    private func reportView(_ report: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Action required: delete the older copies of re-imported threads",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Save Report…") { saveReport(report) }
                    .secondaryActionButtonStyle()
            }
            .padding([.horizontal, .top], 16)

            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.3))

            Text("Also saved to \(AppModel.reportFileURL.path)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func saveReport(_ report: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "threads_to_delete.txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
