import SwiftUI

@main
struct KeybreezeApp: App {
    @StateObject private var appState = AppState()
    
    /// The session VM is lazily created and stored as a strong reference so it outlives
    /// any single view's lifetime (needed for the separate settings/Typing Lab window).
    @State private var sessionVM: SessionViewModel?

    private var resolvedSessionVM: SessionViewModel {
        if let existing = sessionVM {
            return existing
        }
        let vm = SessionViewModel(appState: appState)
        sessionVM = vm
        return vm
    }

    init() {
        AppKitLifecycle.configureMenuBarAgentApp()
    }

    var body: some Scene {
        MenuBarExtra("Keybreeze", systemImage: "wind") {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(resolvedSessionVM)
        }
        .menuBarExtraStyle(.menu)

        // Settings window — uses SwiftUI Window scene with hidden title bar
        // for safe lifecycle management (avoids manual NSWindow teardown crashes).
        Window("Keybreeze Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(resolvedSessionVM)
                .onAppear {
                    AppKitLifecycle.showInDockAndCmdTab()
                }
                .onDisappear {
                    // Cancel predictions to prevent stale callbacks during teardown
                    resolvedSessionVM.cancelCurrentPrediction()
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