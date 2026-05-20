import Combine
import Foundation

/// Shared app state (model selection, backend, model catalogs). Owned at app root; not persisted yet.
@MainActor
final class AppState: ObservableObject {
    @Published var selectedModel: ModelOption
    /// Selected inference backend (Ollama or llama.cpp).
    @Published var selectedBackend: LLMBackend = .ollama {
        didSet {
            guard oldValue != selectedBackend else { return }
            config.backend = selectedBackend
            handleBackendChange(from: oldValue, to: selectedBackend)
        }
    }
    /// Populated from Ollama `GET /api/tags` (same set as `ollama list`).
    @Published private(set) var availableModels: [ModelOption] = []
    /// Empty when healthy; otherwise a short user-visible hint (connection errors, empty catalog).
    @Published var modelCatalogStatus: String = ""

    /// Flat shared backend configuration (backed by the UI-visible `selectedBackend`).
    var config: LLMConfig {
        didSet {
            // Keep the enum in sync with the config for consumers that observe it.
            if config.backend != selectedBackend {
                selectedBackend = config.backend
            }
        }
    }

    /// The llama.cpp server state, observed for readiness gating.
    @Published var llamaCppServerState: LlamaCppService.ServerState = .stopped

    private let urlSession: URLSession

    /// Retained reference to the llama.cpp service so it can manage the server process
    /// across engine rebuilds. `nil` when the active backend is Ollama.
    private var activeLlamaCppService: LlamaCppService?

    init(
        selectedModel: ModelOption? = nil,
        config: LLMConfig = LLMConfig(),
        urlSession: URLSession = .shared
    ) {
        self.config = config
        self.urlSession = urlSession
        self.selectedModel = selectedModel ?? ModelRegistry.defaultModel
        self.selectedBackend = config.backend

        // If the initial backend is llama.cpp, wire up process management.
        if config.backend == .llamaCpp {
            setUpLlamaCppService()
        }
    }

    /// Refresh the model list for whatever backend is currently selected.
    func refreshAvailableModels() async {
        switch selectedBackend {
        case .ollama:
            await refreshAvailableModelsFromOllama()
        case .llamaCpp:
            refreshLlamaCppModels()
        }
    }

    /// Refreshes `availableModels` from the local Ollama server. Keeps prior list on failure if it was non-empty.
    func refreshAvailableModelsFromOllama() async {
        modelCatalogStatus = "Loading models…"
        do {
            let options = try await OllamaLLMService.fetchModelOptions(
                baseURL: config.ollamaBaseURL,
                urlSession: urlSession
            )
            availableModels = options

            guard !options.isEmpty else {
                modelCatalogStatus = "No models found. Run `ollama pull <name>` in a terminal."
                return
            }

            if let match = options.first(where: { $0.ollamaId == selectedModel.ollamaId }) {
                selectedModel = match
            } else {
                selectedModel = options[0]
            }
            modelCatalogStatus = ""
        } catch {
            modelCatalogStatus = error.localizedDescription
            if availableModels.isEmpty {
                selectedModel = ModelRegistry.defaultModel
            }
        }
    }

    /// Scans the GGUF directory for available models.
    func refreshLlamaCppModels() {
        let gguflist = LlamaCppService.scanModels(directory: config.llamaCppModelsDirectory)

        guard !gguflist.isEmpty else {
            modelCatalogStatus = "No GGUF files found in \(config.llamaCppModelsDirectory)"
            availableModels = []
            return
        }

        let options = gguflist.map { gguf in
            ModelOption(
                id: gguf.id,
                displayName: gguf.displayName,
                ollamaId: gguf.displayName,
                ggufPath: gguf.id,
                maxWords: 12,
                verbosityBias: 0.35,
                continuationBias: 0.45,
                instructionStrictness: 0.88,
                temperature: ModelOption.defaultTemperature,
                topP: ModelOption.defaultTopP,
                repeatPenalty: ModelOption.defaultRepeatPenalty,
                presencePenalty: 0.0,
                confidenceThreshold: ModelOption.defaultConfidenceThreshold
            )
        }
        availableModels = options

        if let current = options.first(where: { $0.id == selectedModel.id }) {
            selectedModel = current
        } else {
            selectedModel = options[0]
        }
        modelCatalogStatus = ""
    }

    var canRunPrediction: Bool {
        if selectedBackend == .ollama {
            return !availableModels.isEmpty
        } else {
            return !availableModels.isEmpty && llamaCppServerState.isRunning
        }
    }

    /// Builds an `LLMConfig` reflecting the current settings. Convenience for engine creation.
    var effectiveConfig: LLMConfig {
        var c = config
        c.backend = selectedBackend
        return c
    }

    /// Creates a fresh `PredictionEngine` for the current backend.
    func makeEngine() -> PredictionEngine {
        PredictionEngine(config: effectiveConfig)
    }

    // MARK: - Private

    private func setUpLlamaCppService() {
        let service = LlamaCppService(config: config, urlSession: urlSession)
        service.onStateChange { [weak self] state in
            self?.llamaCppServerState = state
        }
        activeLlamaCppService = service
        llamaCppServerState = service.serverState
    }

    /// Called when the user switches backends. Updates the model list and manages llama-server lifecycle.
    private func handleBackendChange(from old: LLMBackend, to new: LLMBackend) {
        Task {
            switch new {
            case .ollama:
                // Stop the llama.cpp server if it was running
                activeLlamaCppService?.stopServer()
                activeLlamaCppService = nil
                // Refresh Ollama model list
                availableModels = []
                await refreshAvailableModelsFromOllama()
            case .llamaCpp:
                // Wire up process management
                setUpLlamaCppService()
                // Scan GGUF directory
                refreshLlamaCppModels()
                // Auto-launch the server with the selected model if it's a GGUF
                if selectedModel.isGGUF, let path = selectedModel.ggufPath {
                    do {
                        try await activeLlamaCppService?.startServer(modelPath: path)
                    } catch {
                        modelCatalogStatus = "Failed to start llama-server: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// Explicitly stop any running llama.cpp server (e.g. on app quit).
    func stopLlamaCppServer() {
        activeLlamaCppService?.stopServer()
    }
}