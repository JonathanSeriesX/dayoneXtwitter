import SwiftUI

@main
struct TwixodusApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Twixodus", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .frame(minWidth: 720, minHeight: 560)
        }
        .defaultSize(width: 780, height: 710)
    }
}
