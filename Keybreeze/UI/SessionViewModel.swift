import AppKit
import Combine
import Foundation
import OSLog

/// Prediction session view model — the bridge between the user interface and the prediction engine.
/// Acts as both the editor state holder and the observable surface for TypingLab views.
///
/// Modes:
/// - Playground mode (default): predictions are driven by `draftText` in the Typing Lab text field.
/// - System-wide mode: predictions are driven by `SystemWidePredictor` reading the focused app's
///   text field via Accessibility API. The playground's `draftText` is decoupled from the engine.
@MainActor
final class SessionViewModel: ObservableObject {
    private let log = Logger(subsystem: "app.keybreeze", category: "session")

    // MARK: System-Wide Predictor

    /// Bridges external app text into the prediction engine.
    private lazy var systemWidePredictor: SystemWidePredictor = {
        SystemWidePredictor(controller: controller)
    }()

    // MARK: Event Monitors (Tab acceptance)

    /// Local monitor intercepts Tab in the Typing Lab window — can consume the event.
    /// This works everywhere Keybreeze has a focused window: Keystrokes in the
    /// Typing Lab playground, or any future Keybreeze-owned text surface.
    private var localEventMonitor: Any?

    /// Global monitor observes Tab presses in *other* apps — cannot consume, but
    /// we still insert the suggestion via AccessibilityManager.
    private var globalEventMonitor: Any?

    // MARK: Published State — Editor

    @Published var draftText = "" {
        didSet {
            print("draftText changed: '\(draftText)'")
            handleDraftChanged()
        }
    }
    @Published var suggestion = ""
    @Published var statusMessage = "Ready"

    // MARK: Published State — Prediction Mode

    @Published var isPredicting = false

    /// Master enable/disable for the entire app. When on: predictions flow to both the
    /// Typing Lab playground AND system-wide via SystemWidePredictor. When off: everything stops.
    @Published var isEnabled = true {
        didSet {
            print("isEnabled changed to \(isEnabled)")
            if isEnabled {
                controller.start()
                installTabInterceptors()
                startSystemWidePredictor()
                // Trigger prediction for any existing draft text
                if !draftText.isEmpty {
                    controller.editorStateChanged(EditorState(
                        textBeforeCursor: draftText,
                        textAfterCursor: ""
                    ))
                }
            } else {
                controller.stop()
                stopSystemWidePredictor()
                removeTabInterceptors()
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

    /// Suppresses handleDraftChanged() while we're programmatically setting
    /// draftText from acceptWord/acceptSuggestion, so the controller doesn't
    /// receive stale or duplicate editor states.
    private var isAccepting = false

    // MARK: Derived

    var effectiveModelOption: ModelOption {
        appState.selectedModel
    }

    /// Number of accepted predictions since midnight today.
    var dailyAcceptedCount: Int {
        predictionHistory.countTodayAccepted()
    }

    /// Cancels the current in-flight prediction without stopping the scheduler.
    /// Called when the Typing Lab window closes so stale @MainActor callbacks
    /// don't clash with SwiftUI's view teardown cycle.
    func cancelCurrentPrediction() {
        controller.cancelPrediction()
    }

    // MARK: Init

    init(appState: AppState) {
        print("SessionViewModel initialized")
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

        // Auto-start when the app launches
        isEnabled = true
    }

    // MARK: Draft Handling

    private func handleDraftChanged() {
        guard isEnabled, !isAccepting else { return }
        controller.editorStateChanged(EditorState(
            textBeforeCursor: draftText,
            textAfterCursor: ""
        ))
    }

    func draftTextChanged() {
        // Called from TypingLabView.onChange — already handled in didSet
    }

    // MARK: Tab Interception

    /// Installs local and global NSEvent monitors to intercept Tab presses.
    private func installTabInterceptors() {
        removeTabInterceptors()

        // Local monitor: captures Tab in our own windows (Typing Lab).
        // Accepts one word at a time — remaining ghost text stays visible.
        // The prediction engine is suppressed via expectedTextAfterAcceptance
        // so it won't fire a new prediction until the user's next pause.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEnabled, !self.suggestion.isEmpty else { return event }
            if event.keyCode == 48 { // kVK_Tab
                self.acceptWord()
                return nil // Consume the event
            }
            return event
        }

        // Global monitor: observes Tab in other apps. Cannot consume the event,
        // but inserts the first accepted word via AccessibilityManager.
        // Remaining ghost words stay visible for granular acceptance.
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEnabled, !self.suggestion.isEmpty, event.keyCode == 48 else { return }

            let components = self.suggestion.components(separatedBy: .whitespaces)
            guard let first = components.first, !first.isEmpty else { return }

            // Insert only the first word
            AccessibilityManager.shared.insertText(first + " ")

            // Keep remaining words as the suggestion
            self.suggestion = components.dropFirst().joined(separator: " ")
        }
    }

    private func removeTabInterceptors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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

        // Determine the accepted word:
        // If the model's first word repeats the last word the user typed,
        // skip it to avoid duplication (e.g. user types "a " → model predicts "a curious").
        let lastDraftWord = draftText.split(separator: " ").last.flatMap(String.init) ?? ""
        let acceptedWord: String
        let remainingSuggestion: String
        if lastDraftWord == first {
            // First word is already typed — skip it, accept the second word instead
            let rest = Array(components.dropFirst())
            if rest.isEmpty { return }
            acceptedWord = rest[0]
            remainingSuggestion = rest.dropFirst().joined(separator: " ")
        } else {
            acceptedWord = first
            remainingSuggestion = components.dropFirst().joined(separator: " ")
        }

        let newText = draftText + acceptedWord + " "

        // Suppress didSet → handleDraftChanged() so the controller doesn't
        // receive our programmatic text change as a new editor state.
        // The remaining ghost suggestion is already in place, so the user
        // can either Tab again or type — both of which will trigger fresh
        // predictions naturally.
        isAccepting = true
        draftText = newText
        isAccepting = false

        suggestion = remainingSuggestion

        predictionHistory.add(PredictionRecord(
            timestamp: Date(),
            modelDisplayName: effectiveModelOption.displayName,
            mode: currentPredictionMode,
            resolution: .accepted,
            timeToFirstToken: currentTTFT,
            totalTime: currentLatency ?? 0,
            typedContext: draftText,
            generatedContinuation: acceptedWord
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

    // MARK: System-Wide Predictor Lifecycle

    /// Start the system-wide predictor, syncing app gating lists.
    private func startSystemWidePredictor() {
        systemWidePredictor.excludedBundleIDs = excludedBundleIDs
        systemWidePredictor.manualOnlyBundleIDs = manualOnlyBundleIDs
        systemWidePredictor.start()
        log.info("System-wide predictor started")
    }

    /// Stop the system-wide predictor.
    private func stopSystemWidePredictor() {
        systemWidePredictor.stop()
        log.info("System-wide predictor stopped")
    }

    /// The focused app bundle ID from the system-wide predictor (if active).
    var focusedAppBundleID: String? {
        systemWidePredictor.focusedAppBundleID
    }

    /// The focused app display name from the system-wide predictor (if active).
    var focusedAppName: String? {
        systemWidePredictor.focusedAppName
    }

    /// Whether the system-wide predictor is paused.
    var isSystemWidePaused: Bool {
        systemWidePredictor.isPaused
    }

    /// The pause reason from the system-wide predictor.
    var systemWidePauseReason: String {
        systemWidePredictor.pauseReason
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