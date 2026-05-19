import Foundation
import OSLog

/// Runs invisible predictions in the background to gather evaluation data.
/// The engine predicts continuously but NEVER renders ghost text.
/// Instead, generated predictions are compared against actual user typing
/// to measure overlap, usefulness, and timing quality.
@MainActor
final class ShadowPredictor {
    private let engine: PredictionEngine
    private let log = Logger(subsystem: "app.keybreeze", category: "shadow-predictor")

    private var isActive = false
    private var observationGeneration: UInt64 = 0
    private var latestEditorState: EditorState?
    private var modelProvider: () -> ModelOption

    /// Callback with (typedContext, generatedContinuation, ttft, totalTime, mode)
    var onShadowPrediction: ((String, String, TimeInterval?, TimeInterval, String) -> Void)?

init(
    backend: LLMBackend,
    configuration: LLMConfiguration,
    modelProvider: @escaping () -> ModelOption
) {
    self.engine = PredictionEngine(backend: backend, configuration: configuration)
    self.modelProvider = modelProvider
}

    func updateModelProvider(_ provider: @escaping () -> ModelOption) {
        modelProvider = provider
    }

    func start() {
        isActive = true
        log.debug("Shadow predictor started")
    }

    func stop() {
        isActive = false
        engine.cancel()
        log.debug("Shadow predictor stopped")
    }

    /// Call on every editor change. Runs a prediction but does NOT render it.
    func editorStateChanged(_ state: EditorState) {
        guard isActive else { return }
        latestEditorState = state
        observationGeneration &+= 1
        engine.cancel()

        let trimmed = state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return }

        let generation = observationGeneration
        let model = modelProvider()
        let mode = PredictionMode.midType
        let maxWords = mode.maxWords(modelCap: model.maxWords)
        let focused = ContextBuilder.focusedState(from: state)
        let prompt = PromptBuilder.continuationPrompt(for: focused, modelOption: model)

        let startTime = Date()
        var firstTokenTime: Date?
        var accumulated = ""

        engine.predict(
            editorState: state,
            model: model,
            mode: mode,
            logLatency: false,
            onToken: { token in
                guard generation == self.observationGeneration else { return }
                if firstTokenTime == nil { firstTokenTime = Date() }
                accumulated += token
            }
        )

        // Observe completion
        let captureGeneration = generation
        let capturedContext = state.textBeforeCursor
        Task { [weak self] in
            guard let self else { return }
            // Wait for engine to finish
            while self.engine.isRunning && captureGeneration == self.observationGeneration {
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard captureGeneration == self.observationGeneration else { return }

            let totalTime = Date().timeIntervalSince(startTime)
            let ttft = firstTokenTime?.timeIntervalSince(startTime)
            let wordCount = WordLimiter.wordCount(in: accumulated)

            guard wordCount >= 1 else { return }

            self.onShadowPrediction?(capturedContext, accumulated, ttft, totalTime, mode.rawValue)
            self.log.debug("Shadow: \(accumulated) (\(wordCount) words, \(String(format: "%.2f", totalTime * 1000))ms)")
        }
    }
}