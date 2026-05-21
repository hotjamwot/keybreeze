import SwiftUI

@main
struct KeybreezeApp: App {
    @StateObject private var appState = AppState()

    /// The session VM is lazily created and stored as a strong reference so it outlives
    /// any single view's lifetime (needed for the separate Typing Lab window).
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
    }
}
