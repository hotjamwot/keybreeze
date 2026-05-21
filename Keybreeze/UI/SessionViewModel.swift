import AppKit
import Combine
import Foundation
import OSLog

/// Prediction session view model — the bridge between the user interface and the prediction engine.
/// Acts as both the editor state holder and the observable surface for TypingLab views.
@MainActor
final class SessionViewModel: ObservableObject {
    private let log = Logger(subsystem: "app.keybreeze", category: "session")

    // MARK: Published State — Editor

    @Published var draftText = "" {
        didSet { handleDraftChanged() }
    }
    @Published var suggestion = ""
    @Published var statusMessage = "Ready"

    // MARK: Published State — Prediction Mode

    @Published var isPredicting = false
    @Published var isSchedulerActive = false {
        didSet {
            if isSchedulerActive {
                controller.start()
            } else {
                controller.stop()
                suggestion = ""
                currentLatency = nil
                currentTTFT = nil
            }
        }
    }
    @Published var currentPredictionMode = ""
    @Published var correctionState: CorrectionState?

    // MARK: Published State — Model & Tuning

    @Published var aggressionPreset: AggressionPreset = .balanced {
        didSet { applyPreset(aggressionPreset) }
    }
    @Published var tuningEnabled = false
    @Published var tuningMaxWords: Int = 0
    @Published var midTypeWords: Int = 0
    @Published var pauseWords: Int = 0
    @Published var temperature: Double = 0.35
    @Published var topP: Double = 0.85
    @Published var repeatPenalty: Double = 1.02
    @Published var confidenceThreshold: Double = 0.25
    @Published var verbosityBias: Double = 0.35
    @Published var continuationBias: Double = 0.45
    @Published var instructionStrictness: Double = 0.88

    // MARK: Published State — Prompt Editing

    @Published var customSystemPrompt = ""
    @Published var styleNudge = ""

    // MARK: Published State — App Gating

    @Published var excludedBundleIDs: [String] = []
    @Published var manualOnlyBundleIDs: [String] = []

    // MARK: Published State — Diagnostics

    @Published var currentLatency: TimeInterval?
    @Published var currentTTFT: TimeInterval?
    let predictionHistory = PredictionHistory()

    // MARK: Private

    let appState: AppState
    private let controller: CompletionController
    private var lastSuggestion = ""
    private var cancellables = Set<AnyCancellable>()

    // MARK: Derived

    var effectiveModelOption: ModelOption {
        appState.selectedModel
    }

    // MARK: Init

    init(appState: AppState) {
        self.appState = appState
        self.controller = CompletionController(config: appState.config)

        // Wire controller outputs
        controller.$suggestion
            .receive(on: DispatchQueue.main)
            .assign(to: &$suggestion)

        controller.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$statusMessage)

        controller.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPredicting)

        controller.$currentMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.currentPredictionMode = mode?.rawValue ?? ""
            }
            .store(in: &cancellables)

        controller.$currentLatency
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentLatency)

        controller.$currentTTFT
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTTFT)

        // Wire prediction history recording
        controller.onRecordPrediction = { [weak self] record in
            Task { @MainActor in
                self?.predictionHistory.add(record)
            }
        }

        loadSettings()
        // Push initial params to controller
        updateControllerFromAppState()
    }

    // MARK: Draft Handling

    private func handleDraftChanged() {
        guard isSchedulerActive else { return }
        controller.editorStateChanged(EditorState(
            textBeforeCursor: draftText,
            textAfterCursor: ""
        ))
    }

    func draftTextChanged() {
        // Called from TypingLabView.onChange — already handled in didSet
    }

    // MARK: Actions

    func acceptSuggestion() {
        guard !suggestion.isEmpty else { return }

        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = draftText + trimmed + " "
        draftText = newText
        suggestion = ""
        lastSuggestion = ""
        // Tell the controller to expect this text after acceptance echo
        controller.expectedTextAfterAcceptance = newText

        predictionHistory.add(PredictionRecord(
            timestamp: Date(),
            modelDisplayName: effectiveModelOption.displayName,
            mode: currentPredictionMode,
            resolution: .accepted,
            timeToFirstToken: currentTTFT,
            totalTime: currentLatency ?? 0,
            typedContext: draftText,
            generatedContinuation: trimmed
        ))
    }

    func acceptWord() {
        guard !suggestion.isEmpty else { return }

        let components = suggestion.components(separatedBy: .whitespaces)
        guard let first = components.first, !first.isEmpty else { return }

        let newText = draftText + first + " "
        draftText = newText
        suggestion = components.dropFirst().joined(separator: " ")
        // Tell the controller to expect this text after acceptance echo
        controller.expectedTextAfterAcceptance = newText

        predictionHistory.add(PredictionRecord(
            timestamp: Date(),
            modelDisplayName: effectiveModelOption.displayName,
            mode: currentPredictionMode,
            resolution: .accepted,
            timeToFirstToken: currentTTFT,
            totalTime: currentLatency ?? 0,
            typedContext: draftText,
            generatedContinuation: first
        ))
    }

    // MARK: Model Sync

    func syncTuningFromModel() {
        let model = effectiveModelOption
        temperature = model.temperature
        topP = model.topP
        repeatPenalty = model.repeatPenalty
        confidenceThreshold = model.confidenceThreshold
    }

    func updateControllerFromAppState() {
        controller.modelID = effectiveModelOption.ollamaId.isEmpty
            ? effectiveModelOption.id
            : effectiveModelOption.ollamaId
        controller.temperature = temperature
        controller.topP = topP
        controller.maxWords = tuningMaxWords > 0 ? tuningMaxWords : effectiveModelOption.maxWords
        controller.customSystemPrompt = customSystemPrompt
        controller.styleNudge = styleNudge
    }

    // MARK: Preset

    private func applyPreset(_ preset: AggressionPreset) {
        temperature = preset.temperature
        topP = preset.topP
        repeatPenalty = preset.repeatPenalty
        confidenceThreshold = preset.confidenceThreshold
        updateControllerFromAppState()
    }

    // MARK: Settings

    private func loadSettings() {
        let settings = AppSettings.load()
        excludedBundleIDs = settings.appGating.excludedBundleIDs
        manualOnlyBundleIDs = settings.appGating.manualOnlyBundleIDs
        temperature = settings.inference.temperature
        topP = settings.inference.topP
        repeatPenalty = settings.inference.repeatPenalty
        confidenceThreshold = settings.inference.confidenceThreshold
        verbosityBias = settings.tuning.verbosityBias
        continuationBias = settings.tuning.continuationBias
        instructionStrictness = settings.tuning.instructionStrictness
        tuningMaxWords = settings.tuning.tuningMaxWords
        midTypeWords = settings.tuning.midTypeWords
        pauseWords = settings.tuning.pauseWords
        customSystemPrompt = settings.prompt.customSystemPrompt
        styleNudge = settings.prompt.styleNudge
    }

    func saveSettings() {
        var settings = AppSettings.load()
        settings.appGating.excludedBundleIDs = excludedBundleIDs
        settings.appGating.manualOnlyBundleIDs = manualOnlyBundleIDs
        settings.inference.temperature = temperature
        settings.inference.topP = topP
        settings.inference.repeatPenalty = repeatPenalty
        settings.inference.confidenceThreshold = confidenceThreshold
        settings.tuning.verbosityBias = verbosityBias
        settings.tuning.continuationBias = continuationBias
        settings.tuning.instructionStrictness = instructionStrictness
        settings.tuning.tuningMaxWords = tuningMaxWords
        settings.tuning.midTypeWords = midTypeWords
        settings.tuning.pauseWords = pauseWords
        settings.prompt.customSystemPrompt = customSystemPrompt
        settings.prompt.styleNudge = styleNudge
        settings.save()
    }
}