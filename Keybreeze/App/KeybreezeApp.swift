import SwiftUI

@main
struct KeybreezeApp: App {
    @StateObject private var appState = AppState()

    init() {
        AppKitLifecycle.configureMenuBarAgentApp()
    }

    var body: some Scene {
        MenuBarExtra("Keybreeze", systemImage: "wind") {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(appState.sessionViewModel)
        }
        .menuBarExtraStyle(.menu)

        // Settings window — uses SwiftUI Window scene with hidden title bar
        // for safe lifecycle management (avoids manual NSWindow teardown crashes).
        Window("Keybreeze Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.sessionViewModel)
                .onAppear {
                    AppKitLifecycle.showInDockAndCmdTab()
                }
                .onDisappear {
                    // Cancel predictions to prevent stale callbacks during teardown
                    appState.sessionViewModel.cancelCurrentPrediction()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        AppKitLifecycle.restoreToAccessory()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 820, height: 580)
        .commandsRemoved() // Remove menu bar items for this scene
    }
}
