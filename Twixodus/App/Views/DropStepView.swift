// Step 1 of the flow: take the Twitter archive from the user — a dropped
// .zip, a dropped unpacked folder, or one picked through the open panel.

import SwiftUI
import UniformTypeIdentifiers

struct DropStepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if model.isLoadingArchive {
                loadingPanel
            } else {
                dropZone
            }

            if let error = model.loadError, !model.isLoadingArchive {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480)
            }

            Spacer()

            Text("Request your archive [here](https://x.com/settings/download_your_data) — Settings → Download an archive of your data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.zip, .folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.handleDropped(url: url)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: isTargeted)

            Text("Drop your Twitter archive here")
                .font(.title2.weight(.semibold))
            Text("The twitter-….zip you downloaded, or the already-unpacked folder.")
                .foregroundStyle(.secondary)

            Button("Choose…") { showingPicker = true }
                .secondaryActionButtonStyle()
                .padding(.top, 6)
        }
        .frame(maxWidth: 560)
        .padding(.vertical, 56)
        .padding(.horizontal, 32)
        .heroPanelBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in model.handleDropped(url: url) }
                }
            }
            return true
        }
    }

    private var loadingPanel: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(model.loadStage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Big archives take a little while — all the tweet files are parsed up front.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 560)
        .padding(.vertical, 72)
        .padding(.horizontal, 32)
        .heroPanelBackground()
    }
}
