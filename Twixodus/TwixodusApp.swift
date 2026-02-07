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
        window.styleMask.remove(.resizable)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.minSize = NSSize(width: 900, height: 600)
        window.maxSize = NSSize(width: 900, height: 600)

        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
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
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
    }
}
