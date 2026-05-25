import Foundation
import Combine
import AppKit
import OSLog

/// Simplified shared application state.
/// Replaces exploded AppState + ModelSelectionState + BackendState.
@MainActor
final class AppState: ObservableObject {
    private let log = Logger(subsystem: "app.keybreeze", category: "app-state")

    // MARK: Configuration

    @Published var config = LLMConfig() {
        didSet { saveConfig() }
    }

    // MARK: Backend

    @Published var selectedBackend: LLMBackend = .ollama {
        didSet { handleBackendChange(to: selectedBackend) }
    }

    /// Backend process lifecycle manager.
    let backendManager = BackendManager()

    // MARK: Model Selection

    @Published var selectedModel: ModelOption = .defaultModel {
        didSet { handleModelChange(to: selectedModel) }
    }
    @Published private(set) var availableModels: [ModelOption] = []
    @Published var modelCatalogStatus = ""

    // MARK: Ollama Health (legacy — now managed by BackendManager)

    @Published var isOllamaRunning = false
    private var healthCheckTask: Task<Void, Never>?

    // MARK: Session ViewModel

    /// Lazily created and held as a strong reference so it survives SwiftUI
    /// scene lifecycle events (MenuBarExtra + Window recreate body).
    private var _sessionViewModel: SessionViewModel?
    var sessionViewModel: SessionViewModel {
        if let existing = _sessionViewModel {
            return existing
        }
        let vm = SessionViewModel(appState: self)
        _sessionViewModel = vm
        return vm
    }

    // MARK: Derived

    var canRunPrediction: Bool {
        !availableModels.isEmpty
    }

    // MARK: Init

    init() {
        // Wire the BackendManager into AppKitLifecycle for clean termination
        AppKitLifecycle.backendManager = backendManager

        loadConfig()
        loadSelectedModel()
        // refreshModels() is async and will call bootCurrentBackend() once models load.
        // Do NOT call bootCurrentBackend() here — models aren't loaded yet.
        refreshModels()

        // Sync legacy isOllamaRunning to BackendManager state
        backendManager.$isReady
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOllamaRunning)
    }

    deinit {
        healthCheckTask?.cancel()
        // BackendManager handles teardown via AppKitLifecycle willTerminateNotification.
        // deinit is not relied upon (see ARCHITECTURE.md gotcha #2).
    }

    // MARK: Backend Boot

    /// Boot the currently selected backend with the current model.
    /// Called on app launch and after model catalog refresh.
    private func bootCurrentBackend() {
        guard !availableModels.isEmpty else {
            log.info("No models available — skipping backend boot")
            return
        }

        let modelPath: String
        switch selectedBackend {
        case .ollama:
            // For Ollama, the model path isn't a file path — it's a model name used in API payload.
            // BackendManager will handle Ollama health check / spawn.
            modelPath = selectedModel.ollamaId.isEmpty ? selectedModel.id : selectedModel.ollamaId
        case .llamaCpp:
            // For llama.cpp, the model path is the GGUF file path.
            guard let ggufPath = selectedModel.ggufPath, !ggufPath.isEmpty else {
                let name = selectedModel.displayName
                log.warning("No GGUF path for selected model \(name)")
                return
            }
            modelPath = ggufPath
        }

        backendManager.boot(
            backend: selectedBackend,
            modelPath: modelPath,
            ggufDirectory: config.llamaCppModelsDirectory
        )
    }

    // MARK: Backend Change

    private func handleBackendChange(to newBackend: LLMBackend) {
        config.backend = newBackend
        // refreshModels() will scan models for the new backend,
        // then call bootCurrentBackend() which tears down old + boots new.
        refreshModels()
    }

    // MARK: Model Change

    private func handleModelChange(to newModel: ModelOption) {
        saveSelectedModel()

        // If the backend isn't ready yet, just save the selection.
        // bootCurrentBackend() will use the correct model when it runs.
        guard backendManager.isReady else {
            log.info("Model changed to \(newModel.displayName) — backend not ready, deferring to boot")
            return
        }

        switch selectedBackend {
        case .ollama:
            // Ollama model switching is a no-op in BackendManager — just update the API payload.
            // The SessionViewModel's Combine subscriber will trigger CompletionController
            // to use the new model ID on the next prediction.
            log.info("Ollama model changed to \(newModel.displayName) — no process restart needed")
            backendManager.switchModel(
                to: newModel.ollamaId.isEmpty ? newModel.id : newModel.ollamaId,
                ggufDirectory: config.llamaCppModelsDirectory
            )

        case .llamaCpp:
            // llama.cpp requires a full process restart with the new GGUF file
            guard let ggufPath = newModel.ggufPath, !ggufPath.isEmpty else {
                log.warning("No GGUF path for selected model \(newModel.displayName)")
                return
            }
            log.info("llama.cpp model changed to \(newModel.displayName) — restarting server")
            backendManager.switchModel(to: ggufPath, ggufDirectory: config.llamaCppModelsDirectory)
        }
    }

    // MARK: Model Catalog

    func refreshModels() {
        Task {
            modelCatalogStatus = "Loading models..."
            do {
                switch selectedBackend {
                case .ollama:
                    let options = try await fetchOllamaModels()
                    await MainActor.run {
                        self.availableModels = options
                        self.selectCurrentModel(from: options)
                        self.modelCatalogStatus = options.isEmpty ? "No models found. Run `ollama pull <name>`." : ""
                    }
                case .llamaCpp:
                    let options = LLMClient.scanGGUFModels(directory: config.llamaCppModelsDirectory)
                    await MainActor.run {
                        self.availableModels = options
                        self.selectCurrentModel(from: options)
                        self.modelCatalogStatus = options.isEmpty ? "No GGUF files found." : ""
                    }
                }
            } catch {
                await MainActor.run {
                    self.modelCatalogStatus = error.localizedDescription
                }
            }

            // Boot backend now that models are loaded
            await MainActor.run {
                self.bootCurrentBackend()
            }
        }
    }

    private func fetchOllamaModels() async throws -> [ModelOption] {
        let url = config.ollamaBaseURL.appendingPathComponent("api/tags")
        let (data, _) = try await URLSession.shared.data(from: url)

        struct Response: Decodable {
            let models: [Tag]
        }
        struct Tag: Decodable {
            let name: String
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.models.map { ModelOption.option(resolvingOllamaTag: $0.name) }
    }

    private func selectCurrentModel(from options: [ModelOption]) {
        guard !options.isEmpty else { return }
        if !options.contains(where: { $0.id == self.selectedModel.id }) {
            selectedModel = options[0]
        }
    }

    // MARK: Persistence

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "keybreeze.config")
        }
    }

    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: "keybreeze.config"),
           let saved = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            config = saved
            selectedBackend = saved.backend
        }
    }

    private func saveSelectedModel() {
        if let data = try? JSONEncoder().encode(selectedModel) {
            UserDefaults.standard.set(data, forKey: "keybreeze.selectedModel")
        }
    }

    private func loadSelectedModel() {
        if let data = UserDefaults.standard.data(forKey: "keybreeze.selectedModel"),
           let saved = try? JSONDecoder().decode(ModelOption.self, from: data) {
            selectedModel = saved
        }
    }
}
