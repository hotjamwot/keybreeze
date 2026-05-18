import SwiftUI

@main
struct KeybreezeApp: App {
    @StateObject private var appState: AppState
    @StateObject private var predictionTest: PredictionTestViewModel
    @StateObject private var predictionSession: PredictionSessionViewModel

    init() {
        AppKitLifecycle.configureMenuBarAgentApp()
        let sharedAppState = AppState()
        _appState = StateObject(wrappedValue: sharedAppState)
        _predictionTest = StateObject(wrappedValue: PredictionTestViewModel(appState: sharedAppState))
        _predictionSession = StateObject(wrappedValue: PredictionSessionViewModel(appState: sharedAppState))
    }

    var body: some Scene {
        MenuBarExtra("Keybreeze", systemImage: "wind") {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(predictionTest)
                .environmentObject(predictionSession)
        }
        .menuBarExtraStyle(.window)
    }
}
