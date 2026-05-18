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

    private let engine: PredictionEngine
    private let modelProvider: () -> ModelOption
    private let midTypeDebouncer = Debouncer()
    private let pauseDebouncer = Debouncer()
    private let log = Logger(subsystem: "app.keybreeze", category: "prediction-scheduler")
    private var observationGeneration: UInt64 = 0

    init(engine: PredictionEngine, modelProvider: @escaping () -> ModelOption) {
        self.engine = engine
        self.modelProvider = modelProvider
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
    func editorStateChanged(_ state: EditorState) {
        guard isActive else { return }

        latestEditorState = state
        observationGeneration &+= 1
        engine.cancel()
        engine.clearSuggestion()
        notifySuggestion()
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

        engine.predict(editorState: state, model: model, mode: mode)

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
    }

    private func notifySuggestion() {
        onSuggestionChange?(engine.currentSuggestion)
    }

    private func notifyRunning(_ running: Bool) {
        onRunningChange?(running)
    }
}
