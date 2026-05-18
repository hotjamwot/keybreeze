import Combine
import Foundation

/// Shared app state (model selection, Ollama catalog). Owned at app root; not persisted yet.
@MainActor
final class AppState: ObservableObject {
    @Published var selectedModel: ModelOption
    /// Populated from Ollama `GET /api/tags` (same set as `ollama list`).
    @Published private(set) var availableModels: [ModelOption] = []
    /// Empty when healthy; otherwise a short user-visible hint (connection errors, empty catalog).
    @Published private(set) var modelCatalogStatus: String = ""

    private let ollamaConfiguration: OllamaConfiguration
    private let urlSession: URLSession

    init(
        selectedModel: ModelOption? = nil,
        ollamaConfiguration: OllamaConfiguration = OllamaConfiguration(),
        urlSession: URLSession = .shared
    ) {
        self.ollamaConfiguration = ollamaConfiguration
        self.urlSession = urlSession
        self.selectedModel = selectedModel ?? ModelRegistry.defaultModel
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

    var canRunPrediction: Bool {
        !availableModels.isEmpty
    }
}
