//
//  HelixAgent.swift
//  Helix
//

import SwiftUI

@main
struct HelixAgentApp: App {

    // Single shared app state for the entire app
    @StateObject private var appState = HelixAppState()

    // Force initialization of automation manager to react to config changes.
    init() {
        _ = AutomationManager.shared
    }

    var body: some Scene {
        
        // Main chat window
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
            
        }
        // Prevent bizarre resize behavior while we’re iterating
        .windowResizability(.contentSize)
        // If you like the hidden title bar look, you can re-enable this:
        // .windowStyle(.hiddenTitleBar)

        // Menubar entry (Helix lives here when "closed")
        MenuBarExtra("Helix", systemImage: "sparkles") {
            MenuBarContentView()
                .environmentObject(appState)
        }
        // you can tweak style if you want, but this is safe & stable:
        .menuBarExtraStyle(.window)

        // Settings window for editing configuration
        Settings {
            HelixSettingsView()
        }

    }
}
