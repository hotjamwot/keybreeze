import Combine
import Foundation
import OSLog

@MainActor
final class PredictionTestViewModel: ObservableObject {
    @Published private(set) var streamedText: String = ""
    @Published private(set) var statusMessage: String = "Idle"
    @Published private(set) var isRunning: Bool = false

    private let appState: AppState
    private let engine: PredictionEngine
    private let log = Logger(subsystem: "app.keybreeze", category: "prediction-test")
    private var observationTask: Task<Void, Never>?

    /// Sample prefix for Phase 1 harness (no Obsidian yet).
    static let samplePrefix = "The night was unusually quiet and he noticed tha"

    init(appState: AppState, provider: (any LLMProvider)? = nil) {
        self.appState = appState
        self.engine = PredictionEngine(provider: provider)
    }

    func cancel() {
        observationTask?.cancel()
        engine.cancel()
        statusMessage = "Cancelled"
        isRunning = false
    }

    func runTestPrediction() {
        guard !isRunning else { return }

        let model = appState.selectedModel
        isRunning = true
        streamedText = ""
        statusMessage = "Streaming…"

        let state = EditorState(textBeforeCursor: Self.samplePrefix, textAfterCursor: "")

        log.info("Starting stream model=\(model.ollamaId, privacy: .public)")

        engine.predict(editorState: state, model: model, mode: .pause) { token in
            print(token, terminator: "")
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            while self.engine.isRunning {
                self.streamedText = self.engine.currentSuggestion
                try? await Task.sleep(for: .milliseconds(20))
            }
            self.streamedText = self.engine.currentSuggestion
            self.statusMessage = "Done"
            self.isRunning = false
            self.log.info("Stream finished: \(self.streamedText, privacy: .public)")
        }
    }
}
