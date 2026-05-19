import SwiftUI

@main
struct KeybreezeApp: App {
    @StateObject private var appState: AppState
    @StateObject private var predictionSession: PredictionSessionViewModel

    init() {
        AppKitLifecycle.configureMenuBarAgentApp()
        let sharedAppState = AppState(
            ollamaConfiguration: OllamaConfiguration(),
            llamaCppConfiguration: LlamaCppConfiguration()
        )
        _appState = StateObject(wrappedValue: sharedAppState)
        _predictionSession = StateObject(wrappedValue: PredictionSessionViewModel(appState: sharedAppState))
    }

    var body: some Scene {
        MenuBarExtra("Keybreeze", systemImage: "wind") {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(predictionSession)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appState.selectedBackend) { _, _ in
            // Backend changes are handled by AppState.handleBackendChange
        }
    }
}