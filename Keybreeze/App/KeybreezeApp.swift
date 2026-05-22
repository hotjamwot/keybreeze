import SwiftUI

@main
struct KeybreezeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var sessionVM = SessionViewModel(appState: appState)

    init() {
        AppKitLifecycle.configureMenuBarAgentApp()
    }

    var body: some Scene {
        MenuBarExtra("Keybreeze", systemImage: "wind") {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(sessionVM)
        }
        .menuBarExtraStyle(.menu)
    }
}
