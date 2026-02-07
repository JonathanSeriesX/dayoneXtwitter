import AppKit
import SwiftUI

@MainActor
final class TwixodusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configureWindowAppearance(window)
    }

    private func configureWindowAppearance(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)

        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        window.isOpaque = false
        window.backgroundColor = .clear

        let targetRadius: CGFloat = 30

        if let frameView = window.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.masksToBounds = true
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.cornerRadius = targetRadius
        }

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.masksToBounds = true
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.cornerRadius = targetRadius
        }
    }
}

@main
struct TwixodusApp: App {
    @NSApplicationDelegateAdaptor(TwixodusAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 900)
        .windowResizability(.contentSize)
    }
}
