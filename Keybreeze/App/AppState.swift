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

    // MARK: Model Selection

    @Published var selectedModel: ModelOption = .defaultModel {
        didSet { saveSelectedModel() }
    }
    @Published private(set) var availableModels: [ModelOption] = []
    @Published var modelCatalogStatus = ""

    // MARK: Ollama Health

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
        loadConfig()
        loadSelectedModel()
        refreshModels()
        startOllamaHealthCheck()
    }

    deinit {
        healthCheckTask?.cancel()
    }

    // MARK: Ollama Health Check

    private func startOllamaHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkOllamaHealth()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // every 5 seconds
            }
        }
    }

    private func checkOllamaHealth() async {
        let url = config.ollamaBaseURL
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                self.isOllamaRunning = (response as? HTTPURLResponse)?.statusCode == 200
            }
        } catch {
            await MainActor.run {
                self.isOllamaRunning = false
            }
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
        if !options.contains(where: { $0.id == selectedModel.id }) {
            selectedModel = options[0]
        }
    }

    // MARK: Backend Change

    private func handleBackendChange(to newBackend: LLMBackend) {
        config.backend = newBackend
        refreshModels()
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