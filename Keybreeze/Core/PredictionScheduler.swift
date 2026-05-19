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
    /// Provides mode, ttft, totalTime, the resulting text, whether it was cancelled,
    /// and the context text that was used at prediction launch time.
    var onPredictionComplete: ((_ mode: PredictionMode, _ ttft: TimeInterval?, _ totalTime: TimeInterval, _ text: String, _ cancelled: Bool, _ contextAtLaunch: String) -> Void)?

    private let engine: PredictionEngine
    private var modelProvider: () -> ModelOption
    private var promptOverrides: () -> (system: String, styleNudge: String) = { ("", "") }
    private let midTypeDebouncer = Debouncer()
    private let pauseDebouncer = Debouncer()
    private let log = Logger(subsystem: "app.keybreeze", category: "prediction-scheduler")
    private var observationGeneration: UInt64 = 0
    /// Captured context text at prediction launch time, stored so completion callbacks
    /// record the correct context (not the text that may have changed by completion time).
    private var contextSnapshotAtLaunch: String = ""

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

    /// Call on every editor change (keystroke). Reschedules both modes.
    /// Does NOT cancel in-flight predictions — they continue streaming until a new one actually fires.
    /// Does NOT clear the suggestion — the old prediction stays visible until the new one arrives.
    /// Note: observationGeneration is NOT bumped here — it's only bumped in runPrediction() when a
    /// new prediction actually launches. This ensures in-flight observers aren't killed prematurely
    /// by a keystroke that doesn't start a new prediction (because engine.isRunning was true).
    func editorStateChanged(_ state: EditorState) {
        guard isActive else { return }

        latestEditorState = state

        // Cancel debouncers but NOT the engine — let in-flight predictions finish
        midTypeDebouncer.cancel()
        pauseDebouncer.cancel()

        let trimmed = state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            notifyRunning(false)
            onStatusChange?("Waiting for more text…")
            return
        }

        onStatusChange?("Typing…")

        midTypeDebouncer.schedule(after: .milliseconds(PredictionMode.midType.debounceMilliseconds)) { [weak self] in
            guard let self else { return }
            // If the engine is already predicting, don't cancel it — let it finish.
            // A slightly stale suggestion is infinitely better than no suggestion.
            // The delayed start means predictions survive long enough for the user to see and accept them.
            if engine.isRunning {
                log.debug("Mid-type debounce fired but engine already running — letting it finish")
                return
            }
            self.runPrediction(mode: .midType)
        }

        pauseDebouncer.schedule(after: .milliseconds(PredictionMode.pause.debounceMilliseconds)) { [weak self] in
            guard let self else { return }
            if engine.isRunning {
                log.debug("Pause debounce fired but engine already running — letting it finish")
                return
            }
            self.runPrediction(mode: .pause)
        }
    }

    private func runPrediction(mode: PredictionMode) {
        guard isActive, let state = latestEditorState else { return }

        let model = modelProvider()
        onStatusChange?("Predicting (\(mode.rawValue))…")
        onModeChange?(mode)
        notifyRunning(true)

        log.debug("Scheduling predict mode=\(mode.rawValue, privacy: .public)")

        // Snapshot the context at prediction launch time
        contextSnapshotAtLaunch = state.textBeforeCursor

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
        // Capture the context that was current when this prediction was launched
        let context = contextSnapshotAtLaunch

        while engine.isRunning {
            guard generation == observationGeneration else {
                // Prediction was overtaken by a newer one — fire completion with cancelled flag
                if let metrics = engine.lastRunMetrics {
                    onPredictionComplete?(mode, metrics.ttft, metrics.totalTime, engine.currentSuggestion, true, context)
                }
                return
            }
            notifySuggestion()
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard generation == observationGeneration else {
            if let metrics = engine.lastRunMetrics {
                onPredictionComplete?(mode, metrics.ttft, metrics.totalTime, engine.currentSuggestion, true, context)
            }
            return
        }
        notifySuggestion()
        notifyRunning(false)
        if isActive {
            onStatusChange?("Ready (\(mode.rawValue))")
        }

        // Fire completion callback for history tracking
        if let metrics = engine.lastRunMetrics {
            onPredictionComplete?(mode, metrics.ttft, metrics.totalTime, engine.currentSuggestion, metrics.cancelled, context)
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
