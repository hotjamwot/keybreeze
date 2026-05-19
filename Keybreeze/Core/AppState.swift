import Combine
import Foundation

/// Shared app state (model selection, backend, Ollama catalog / GGUF catalog). Owned at app root; not persisted yet.
@MainActor
final class AppState: ObservableObject {
    @Published var selectedModel: ModelOption
    /// Selected inference backend (Ollama or llama.cpp).
    @Published var selectedBackend: LLMBackend = .ollama {
        didSet {
            guard oldValue != selectedBackend else { return }
            handleBackendChange(from: oldValue, to: selectedBackend)
        }
    }
    /// Populated from Ollama `GET /api/tags` (same set as `ollama list`).
    @Published private(set) var availableModels: [ModelOption] = []
    /// Empty when healthy; otherwise a short user-visible hint (connection errors, empty catalog).
    @Published var modelCatalogStatus: String = ""
    /// The llama.cpp process manager (starts/stops `llama-server`).
    @Published private(set) var llamaCppProcessManager: LlamaCppProcessManager

    let ollamaConfiguration: OllamaConfiguration
    let llamaCppConfiguration: LlamaCppConfiguration
    private let urlSession: URLSession

    init(
        selectedModel: ModelOption? = nil,
        selectedBackend: LLMBackend = .ollama,
        ollamaConfiguration: OllamaConfiguration = OllamaConfiguration(),
        llamaCppConfiguration: LlamaCppConfiguration = LlamaCppConfiguration(),
        urlSession: URLSession = .shared
    ) {
        self.ollamaConfiguration = ollamaConfiguration
        self.llamaCppConfiguration = llamaCppConfiguration
        self.urlSession = urlSession
        self.selectedModel = selectedModel ?? ModelRegistry.defaultModel
        self.selectedBackend = selectedBackend
        self.llamaCppProcessManager = LlamaCppProcessManager(configuration: llamaCppConfiguration)
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
            let tags = try await OllamaModelCatalog.fetchInstalledTags(
                configuration: ollamaConfiguration,
                urlSession: urlSession
            )
            let options = tags.map { ModelRegistry.option(resolvingOllamaTag: $0) }
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
        let gguflist = LlamaCppModelCatalog.scanDirectory(llamaCppConfiguration.modelsDirectory)

        guard !gguflist.isEmpty else {
            modelCatalogStatus = "No GGUF files found in \(llamaCppConfiguration.modelsDirectory)"
            availableModels = []
            return
        }

        let options = gguflist.map { gguf in
            ModelOption(
                id: gguf.id,
                displayName: gguf.displayName,
                ollamaId: gguf.displayName, // Use display name for GGUF models so logs and prediction records have a meaningful identifier
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

        // Pick the first model by default, or keep current selection if still available.
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
            // llama.cpp requires the server to be running
            return !availableModels.isEmpty && llamaCppProcessManager.state.isRunning
        }
    }

    /// Called when the user switches backends. Updates the model list and manages llama-server lifecycle.
    private func handleBackendChange(from old: LLMBackend, to new: LLMBackend) {
        Task {
            switch new {
            case .ollama:
                // If switching away from llama.cpp, stop the server
                llamaCppProcessManager.stop()
                // Refresh Ollama model list
                availableModels = []
                await refreshAvailableModelsFromOllama()
            case .llamaCpp:
                // Scan GGUF directory
                refreshLlamaCppModels()
                // Auto-launch the server with the selected model if it's a GGUF
                if selectedModel.isGGUF, let path = selectedModel.ggufPath {
                    do {
                        try await llamaCppProcessManager.start(modelPath: path)
                    } catch {
                        modelCatalogStatus = "Failed to start llama-server: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// MARK: - LlamaCppProcessManager.State helpers

extension LlamaCppProcessManager.State {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isStartingOrRunning: Bool {
        switch self {
        case .running, .starting: return true
        case .stopped, .failed: return false
        }
    }
}