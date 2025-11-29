import SwiftUI

@main
struct HelixAgent: App {
    @StateObject private var appState: HelixAppState

    init() {
        _appState = StateObject(wrappedValue: HelixAppState())
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
        }
        .defaultSize(width: 820, height: 600)

        // Menu bar assistant
        MenuBarExtra("Helix", systemImage: "sparkles") {
            MenuBarContentView()
                .environmentObject(appState)
        }
    }
}
