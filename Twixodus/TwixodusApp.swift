import AppKit
import SwiftUI

final class TwixodusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct TwixodusApp: App {
    @NSApplicationDelegateAdaptor(TwixodusAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1080, height: 900)
        .windowResizability(.contentSize)
    }
}
