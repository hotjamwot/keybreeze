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

    /// A lazily-built override model that merges the base model with slider values.
    private var _tunedModel: ModelOption?

    var effectiveModelOption: ModelOption {
        _tunedModel ?? appState.selectedModel
    }

    // MARK: — Private

    private let appState: AppState
    private let scheduler: PredictionScheduler

    init(appState: AppState, engine: PredictionEngine? = nil) {
        self.appState = appState
        let sharedEngine = engine ?? PredictionEngine()
        // Build scheduler with a fallback provider that doesn't capture self.
        // We immediately reassign the provider below to use self.effectiveModelOption.
        self.scheduler = PredictionScheduler(engine: sharedEngine) {
            appState.selectedModel
        }

        scheduler.onSuggestionChange = { [weak self] text in
            guard let self else { return }
            // Persist the last non-empty suggestion so it doesn't flash away when the engine clears.
            if !text.isEmpty {
                self.lastDisplayedSuggestion = text
                self.suggestion = text
            } else if !self.lastDisplayedSuggestion.isEmpty {
                // Keep the old suggestion visible; the engine will push a new one soon.
                self.suggestion = self.lastDisplayedSuggestion
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

        // Now self is fully initialized — swap in the proper model provider.
        scheduler.updateModelProvider { [weak self] in
            self?.effectiveModelOption ?? appState.selectedModel
        }
    }

    func draftTextChanged() {
        guard isSchedulerActive else { return }
        pushEditorState()
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
            instructionStrictness: instructionStrictness
        )
    }

    /// Called when `tuningEnabled` is toggled on to sync sliders from the base model.
    func syncTuningFromModel() {
        let base = appState.selectedModel
        verbosityBias = base.verbosityBias
        continuationBias = base.continuationBias
        instructionStrictness = base.instructionStrictness
        tuningMaxWords = base.maxWords
        updateTunedModel()
    }
}
