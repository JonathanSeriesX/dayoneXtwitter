// Design helpers: on Tahoe (macOS 26+) the standard controls pick up Liquid
// Glass automatically because the app is built with the 26 SDK; these helpers
// add the explicitly-glass variants where they matter, while Sequoia keeps
// the classic styles.

import SwiftUI

extension View {
    /// The primary action button: glass-prominent on Tahoe, bordered-prominent before.
    @ViewBuilder
    func primaryActionButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// A secondary action: plain glass on Tahoe, bordered before.
    @ViewBuilder
    func secondaryActionButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A soft glass panel behind hero content (the drop zone); a plain
    /// material panel before Tahoe.
    @ViewBuilder
    func heroPanelBackground(cornerRadius: CGFloat = 24) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
            )
        }
    }
}
