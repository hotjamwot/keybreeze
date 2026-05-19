import Combine
import Foundation

/// Phase 2.5 harness: simulated typing field wired to the prediction scheduler,
/// with inline ghost text and runtime tuning controls.
@MainActor
final class PredictionSessionViewModel: ObservableObject {
    @Published var draftText: String = "The night was unusually quiet and he noticed "
    @Published private(set) var suggestion: String = ""
    /// The last non-empty suggestion we displayed; persists across engine resets to avoid flicker.
    private var lastDisplayedSuggestion: String = ""
    @Published private(set) var statusMessage: String = "Scheduler stopped"
    @Published private(set) var isPredicting: Bool = false
    @Published private(set) var currentPredictionMode: String = ""
    @Published var isSchedulerActive: Bool = false {
        didSet {
            if isSchedulerActive {
                scheduler.start()
                pushEditorState()
            } else {
                scheduler.stop()
                suggestion = ""
                isPredicting = false
                currentPredictionMode = ""
                statusMessage = "Scheduler stopped"
            }
        }
    }

    // MARK: — Runtime tuning overrides

    /// If `true`, the sliders below override the corresponding values on the selected `ModelOption`.
    @Published var tuningEnabled: Bool = false

    @Published var verbosityBias: Double = 0.35 {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
    @Published var continuationBias: Double = 0.45 {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
    @Published var instructionStrictness: Double = 0.88 {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
    /// Overrides `maxWords` on the model. 0 means "use model default".
    @Published var tuningMaxWords: Int = 0 {
        didSet { if tuningEnabled { updateTunedModel() } }
    }

    // MARK: — Typing Lab runtime parameters

    @Published var temperature: Double = ModelOption.defaultTemperature {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
    @Published var topP: Double = ModelOption.defaultTopP {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
    @Published var repeatPenalty: Double = ModelOption.defaultRepeatPenalty {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
    @Published var confidenceThreshold: Double = ModelOption.defaultConfidenceThreshold {
        didSet { if tuningEnabled { updateTunedModel() } }
    }
@Published var customSystemPrompt: String = PromptBuilder.defaultSystemPrompt
@Published var styleNudge: String = ""

/// Behaviour aggression preset
@Published var aggressionPreset: AggressionPreset = .balanced {
    didSet { applyPreset() }
}

// No need for this property; UI binds directly to appState.selectedBackend

/// A lazily-built override model that merges the base model with slider values.
private var _tunedModel: ModelOption?

var effectiveModelOption: ModelOption {
    _tunedModel ?? appState.selectedModel
}

    // MARK: — Private

    let appState: AppState
    private let scheduler: PredictionScheduler
    /// Prevents suggestion updates from the scheduler after tab acceptance until user types again
    @Published private var suggestionLocked = false

init(appState: AppState, engine: PredictionEngine? = nil) {
    self.appState = appState
    // Create a unified configuration from the appState's configurations
    let config = LLMConfiguration(
        ollamaConfiguration: appState.ollamaConfiguration,
        llamaCppConfiguration: appState.llamaCppConfiguration
    )
    let sharedEngine = engine ?? PredictionEngine(
        backend: appState.selectedBackend,
        configuration: config
    )
    // Build scheduler with a fallback provider that doesn't capture self.
    // We immediately reassign the provider below to use self.effectiveModelOption.
    self.scheduler = PredictionScheduler(engine: sharedEngine) {
        appState.selectedModel
    }

    scheduler.onSuggestionChange = { [weak self] text in
        guard let self else { return }
        // Dispatch to main thread to safely check lock and update UI
        DispatchQueue.main.async {
            // If suggestion is locked, ignore updates from the scheduler
            // to keep the original remaining words visible after tab accept
            if self.suggestionLocked {
                return
            }
            // Persist the last non-empty suggestion so it doesn't flash away when the engine clears.
            if !text.isEmpty {
                self.lastDisplayedSuggestion = text
                self.suggestion = text
            } else if !self.lastDisplayedSuggestion.isEmpty {
                // Keep the old suggestion visible; the engine will push a new one soon.
                self.suggestion = self.lastDisplayedSuggestion
            }
        }
    }
    scheduler.onRunningChange = { [weak self] running in
        self?.isPredicting = running
    }
    scheduler.onStatusChange = { [weak self] status in
        self?.statusMessage = status
    }
    scheduler.onModeChange = { [weak self] mode in
        self?.currentPredictionMode = mode?.rawValue ?? ""
    }

    // Wire up history recording when predictions complete
    scheduler.onPredictionComplete = { [weak self] mode, ttft, totalTime, text, cancelled in
        guard let self else { return }
        recordPrediction(
            context: draftText,
            continuation: text,
            ttft: ttft,
            totalTime: totalTime,
            mode: mode.rawValue,
            resolution: cancelled ? .cancelled : .ignored
        )
    }

    // Now self is fully initialized — swap in the proper model provider.
    scheduler.updateModelProvider { [weak self] in
        self?.effectiveModelOption ?? appState.selectedModel
    }
    // Wire runtime prompt overrides from the Typing Lab
    scheduler.updatePromptOverrides { [weak self] in
        guard let self else { return ("", "") }
        return (self.customSystemPrompt, self.styleNudge)
    }
}

    func draftTextChanged() {
        guard isSchedulerActive else { return }
        // Unlock the suggestion when user types, allowing fresh predictions
        suggestionLocked = false
        pushEditorState()
    }

    /// Accept the current suggestion: append only the first word to draftText
    /// and update the suggestion to remove the accepted word.
    /// Returns the text that was accepted, or empty if no suggestion.
    @discardableResult
    func acceptSuggestion() -> String {
        guard !suggestion.isEmpty else { return "" }
        
        // Split the suggestion into first word and the rest
        let components = suggestion.components(separatedBy: .whitespaces)
        let firstWord = components.first ?? ""
        let remaining = components.count > 1 ? components.dropFirst().joined(separator: " ") : ""
        
        guard !firstWord.isEmpty else {
            return ""
        }
        
        let accepted = firstWord
        
        // Append only the first word
        draftText.append(accepted)
        draftText.append(" ") // Add a space after the word
        
        // Update suggestion to the remaining text (trim leading spaces)
        suggestion = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Update lastDisplayedSuggestion to the remaining words so it's used as fallback
        lastDisplayedSuggestion = suggestion
        
        // Lock the suggestion to prevent updates from the scheduler
        // so the remaining words stay visible until user types again
        suggestionLocked = true
        
        // Record this prediction as accepted for history tracking
        if let modeStr = currentPredictionMode.isEmpty ? nil : currentPredictionMode {
            // Record the context before the accepted word and the accepted word itself
            let contextBefore = String(draftText.dropLast(accepted.count + 1)) // +1 for the space
            recordPrediction(
                context: contextBefore,
                continuation: accepted,
                ttft: nil,
                totalTime: 0,
                mode: modeStr,
                resolution: .accepted
            )
        }
        
        // If there's no remaining suggestion, clear the last displayed suggestion
        if suggestion.isEmpty {
            lastDisplayedSuggestion = ""
        }
        
        // Push the new state so the engine can start predicting from the updated text
        pushEditorState()
        
        return accepted
    }

    private func pushEditorState() {
        let state = EditorState(textBeforeCursor: draftText, textAfterCursor: "")
        scheduler.editorStateChanged(state)
    }

    /// Rebuilds the tuned model override from the base model + slider values.
    private func updateTunedModel() {
        let base = appState.selectedModel
        _tunedModel = ModelOption(
            id: base.id,
            displayName: base.displayName + " (tuned)",
            ollamaId: base.ollamaId,
            maxWords: tuningMaxWords > 0 ? tuningMaxWords : base.maxWords,
            verbosityBias: verbosityBias,
            continuationBias: continuationBias,
            instructionStrictness: instructionStrictness,
            temperature: temperature,
            topP: topP,
            repeatPenalty: repeatPenalty,
            confidenceThreshold: confidenceThreshold
        )
    }

    /// Called when `tuningEnabled` is toggled on to sync sliders from the base model.
    func syncTuningFromModel() {
        let base = appState.selectedModel
        verbosityBias = base.verbosityBias
        continuationBias = base.continuationBias
        instructionStrictness = base.instructionStrictness
        tuningMaxWords = base.maxWords
        temperature = base.temperature
        topP = base.topP
        repeatPenalty = base.repeatPenalty
        confidenceThreshold = base.confidenceThreshold
        updateTunedModel()
    }

    // MARK: — Aggression presets

    func applyPreset() {
        switch aggressionPreset {
        case .conservative:
            verbosityBias = 0.15
            continuationBias = 0.7
            instructionStrictness = 0.95
            temperature = 0.4
            topP = 0.85
            confidenceThreshold = 0.5
            tuningMaxWords = 4
        case .balanced:
            verbosityBias = 0.35
            continuationBias = 0.45
            instructionStrictness = 0.88
            temperature = 0.7
            topP = 0.9
            confidenceThreshold = 0.25
            tuningMaxWords = 0
        case .aggressive:
            verbosityBias = 0.6
            continuationBias = 0.2
            instructionStrictness = 0.7
            temperature = 0.9
            topP = 0.95
            confidenceThreshold = 0.1
            tuningMaxWords = 0
        }
        tuningEnabled = true
        updateTunedModel()
    }

    // MARK: — Prediction history tracking

    private(set) var predictionHistory = PredictionHistory()

    /// Call when a prediction completes to record it in history.
    func recordPrediction(
        context: String,
        continuation: String,
        ttft: TimeInterval?,
        totalTime: TimeInterval,
        mode: String,
        resolution: PredictionResolution
    ) {
        let model = effectiveModelOption
        let record = PredictionRecord(
            id: UUID(),
            timestamp: Date(),
            typedContext: context,
            generatedContinuation: continuation,
            timeToFirstToken: ttft,
            totalTime: totalTime,
            resolution: resolution,
            modelId: model.ollamaId,
            modelDisplayName: model.displayName,
            mode: mode,
            parameters: PredictionParametersSnapshot(
                verbosityBias: model.verbosityBias,
                continuationBias: model.continuationBias,
                instructionStrictness: model.instructionStrictness,
                maxWords: model.maxWords,
                temperature: model.temperature,
                topP: model.topP
            )
        )
        predictionHistory.append(record)
    }
}

/// High-level behaviour presets for tuning suggestion frequency and style.
enum AggressionPreset: String, CaseIterable, Sendable {
    case conservative = "Conservative"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
}