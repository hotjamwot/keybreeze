import Foundation
import OSLog

/// Debounced prediction loop: mid-type (fast) and pause (longer) modes. No UI dependency.
@MainActor
final class PredictionScheduler {
    private(set) var latestEditorState: EditorState?
    private(set) var isActive = false

    var onSuggestionChange: ((String) -> Void)?
    var onRunningChange: ((Bool) -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onModeChange: ((PredictionMode?) -> Void)?
    /// Called when a prediction finishes (normal completion or cancellation).
    /// Provides mode, ttft, totalTime, the resulting text, and whether it was cancelled.
    var onPredictionComplete: ((_ mode: PredictionMode, _ ttft: TimeInterval?, _ totalTime: TimeInterval, _ text: String, _ cancelled: Bool) -> Void)?

    private let engine: PredictionEngine
    private var modelProvider: () -> ModelOption
    private var promptOverrides: () -> (system: String, styleNudge: String) = { ("", "") }
    private let midTypeDebouncer = Debouncer()
    private let pauseDebouncer = Debouncer()
    private let log = Logger(subsystem: "app.keybreeze", category: "prediction-scheduler")
    private var observationGeneration: UInt64 = 0

    init(engine: PredictionEngine, modelProvider: @escaping () -> ModelOption) {
        self.engine = engine
        self.modelProvider = modelProvider
    }

    /// Overrides for custom prompts from the Typing Lab (runtime prompt editing).
    func updatePromptOverrides(_ provider: @escaping () -> (system: String, styleNudge: String)) {
        promptOverrides = provider
    }

    /// Allows post-init replacement of the model provider (e.g. after `self` is fully initialized in the owner).
    func updateModelProvider(_ provider: @escaping () -> ModelOption) {
        modelProvider = provider
    }

    func start() {
        isActive = true
        onStatusChange?("Scheduler active")
    }

    func stop() {
        isActive = false
        midTypeDebouncer.cancel()
        pauseDebouncer.cancel()
        engine.cancel()
        engine.clearSuggestion()
        notifySuggestion()
        notifyRunning(false)
        onStatusChange?("Scheduler stopped")
    }

    /// Call on every editor change (keystroke). Cancels stale work and reschedules both modes.
    /// Does NOT clear the suggestion — the old prediction stays visible until the new one arrives.
    func editorStateChanged(_ state: EditorState) {
        guard isActive else { return }

        latestEditorState = state
        observationGeneration &+= 1
        engine.cancel()
        // Keep the old suggestion visible until the new prediction streams in.
        notifyRunning(false)

        midTypeDebouncer.cancel()
        pauseDebouncer.cancel()

        let trimmed = state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            onStatusChange?("Waiting for more text…")
            return
        }

        onStatusChange?("Typing…")

        midTypeDebouncer.schedule(after: .milliseconds(PredictionMode.midType.debounceMilliseconds)) { [weak self] in
            self?.runPrediction(mode: .midType)
        }

        pauseDebouncer.schedule(after: .milliseconds(PredictionMode.pause.debounceMilliseconds)) { [weak self] in
            self?.runPrediction(mode: .pause)
        }
    }

    private func runPrediction(mode: PredictionMode) {
        guard isActive, let state = latestEditorState else { return }

        let model = modelProvider()
        onStatusChange?("Predicting (\(mode.rawValue))…")
        notifyRunning(true)

        log.debug("Scheduling predict mode=\(mode.rawValue, privacy: .public)")

        let prompts = promptOverrides()
        engine.predict(
            editorState: state,
            model: model,
            mode: mode,
            customSystemPrompt: prompts.system,
            styleNudge: prompts.styleNudge
        )

        observationGeneration &+= 1
        let generation = observationGeneration
        Task { [weak self] in
            guard let self else { return }
            await self.observeEngineUntilIdle(mode: mode, generation: generation)
        }
    }

    private func observeEngineUntilIdle(mode: PredictionMode, generation: UInt64) async {
        while engine.isRunning {
            guard generation == observationGeneration else { return }
            notifySuggestion()
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard generation == observationGeneration else { return }
        notifySuggestion()
        notifyRunning(false)
        if isActive {
            onStatusChange?("Ready (\(mode.rawValue))")
        }

        // Fire completion callback for history tracking
        if let metrics = engine.lastRunMetrics {
            onPredictionComplete?(mode, metrics.ttft, metrics.totalTime, engine.currentSuggestion, metrics.cancelled)
        }
    }

    private func notifySuggestion() {
        let text = engine.currentSuggestion
        if !text.isEmpty {
            log.debug("Suggestion: \"\(text, privacy: .public)\"")
        }
        onSuggestionChange?(text)
    }

    private func notifyRunning(_ running: Bool) {
        onRunningChange?(running)
    }
}
