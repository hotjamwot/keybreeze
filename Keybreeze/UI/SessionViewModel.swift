import AppKit
import Combine
import Foundation
import OSLog

// MARK: - Suggestion Session State

/// Manages an active suggestion session with reconciliation support.
/// When the user types characters that match the visible ghost text, we
/// advance the session locally — providing instant response without
/// waiting for the server.
@MainActor
final class SuggestionSessionManager {
    /// The current active session, if any.
    private(set) var session: ActiveSuggestionSession?

    /// Pending insertion sentinel for post-Tab AX lag tolerance.
    private(set) var pendingInsertionConsumedCount: Int?

    /// The last overlay state we published.
    private(set) var overlayState: OverlayState = .hidden(reason: "No active suggestion")
    
    /// The visible text currently shown to the user (the remaining suggestion text).
    private(set) var visibleSuggestion: String = ""
    
    /// Reset for a new session.
    func reset() {
        session = nil
        pendingInsertionConsumedCount = nil
        overlayState = .hidden(reason: "No active suggestion")
        visibleSuggestion = ""
    }
    
    /// Start a new suggestion session from a controller prediction.
    func startSession(with suggestion: String, baseContext: FocusedInputContext, latency: TimeInterval) {
        guard !suggestion.isEmpty else {
            reset()
            return
        }
        let newSession = ActiveSuggestionSession(
            baseContext: baseContext,
            fullText: suggestion,
            latency: latency
        )
        session = newSession
        visibleSuggestion = suggestion
        overlayState = .visible(
            text: suggestion,
            geometry: SuggestionOverlayGeometry(
                caretRect: baseContext.caretRect,
                inputFrameRect: baseContext.inputFrameRect,
                caretQuality: baseContext.caretQuality,
                observedCharWidth: baseContext.observedCharWidth
            )
        )
    }
    
    /// Attempt to advance the session locally when the user types characters
    /// that match the beginning of the remaining ghost text.
    /// Returns true if the suggestion was advanced (meaning we consumed the
    /// typed characters locally without needing a server request).
    func advanceWithTypedCharacters(_ typed: String) -> Bool {
        guard let session else { return false }
        guard let advanced = SuggestionSessionReconciler.advanceIfTypedCharactersMatch(typed, session: session) else {
            return false
        }
        self.session = advanced
        visibleSuggestion = advanced.remainingText
        if advanced.isExhausted {
            overlayState = .hidden(reason: "Suggestion fully consumed by typing")
            visibleSuggestion = ""
        } else {
            overlayState = .visible(
                text: advanced.remainingText,
                geometry: SuggestionOverlayGeometry(
                    caretRect: advanced.baseContext.caretRect,
                    inputFrameRect: advanced.baseContext.inputFrameRect,
                    caretQuality: advanced.baseContext.caretQuality,
                    observedCharWidth: advanced.baseContext.observedCharWidth
                )
            )
        }
        return true
    }
    
    /// Reconcile the session with live editor state from AX.
    func reconcile(with liveContext: FocusedInputContext) -> SuggestionSessionReconciliation {
        guard let session else {
            return .invalid("No active session to reconcile")
        }
        let result = SuggestionSessionReconciler.reconcile(
            session: session,
            with: liveContext,
            pendingInsertionConsumedCount: pendingInsertionConsumedCount
        )
        if case let .valid(updatedSession, _, newPending) = result {
            self.session = updatedSession
            pendingInsertionConsumedCount = newPending
            visibleSuggestion = updatedSession.remainingText
            if updatedSession.isExhausted {
                overlayState = .hidden(reason: "Suggestion exhausted")
                visibleSuggestion = ""
            } else {
                overlayState = .visible(
                    text: updatedSession.remainingText,
                    geometry: SuggestionOverlayGeometry(
                        caretRect: updatedSession.baseContext.caretRect,
                        inputFrameRect: updatedSession.baseContext.inputFrameRect,
                        caretQuality: updatedSession.baseContext.caretQuality,
                        observedCharWidth: updatedSession.baseContext.observedCharWidth
                    )
                )
            }
        } else if case .invalid = result {
            reset()
        }
        return result
    }
}

// MARK: - String Utilities

private extension String {
    /// The characters that Keybreeze treats as typed text mutations eligible for local reconciliation.
    /// Control characters (backspace, return, etc.) require server regeneration.
    var isTypedTextInput: Bool {
        guard !isEmpty else { return false }
        return unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

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

    // MARK: Context Presets

    /// Pre-built test scenarios that populate the playground with realistic text
    /// so the user can rapidly test prediction quality across different writing contexts.
    enum ContextPreset: String, CaseIterable {
        case shortStory = "Short Story"
        case emailDraft = "Email Draft"
        case markdownNotes = "Markdown Notes"
        case creativeWriting = "Creative Writing"

        var text: String {
            switch self {
            case .shortStory:
                return "Hayden was sitting on the porch swing. He watched the sunset as the colors faded into darkness."
            case .emailDraft:
                return "Hi Sarah,\n\nI wanted to follow up on our conversation from yesterday. I think the best approach would be to"
            case .markdownNotes:
                return "## Implementation Plan\n\nThe keybreeze architecture is built around three core components:\n\n1. **CompletionController** — prediction orchestrator with debouncing and streaming\n2. **LLMClient** — single HTTP client for Ollama and llama.cpp\n3. **SessionViewModel** — bridge between UI and prediction engine\n\nThe data flow starts when the user"
            case .creativeWriting:
                return "I remember the first time I saw the ocean at night. The waves were crashing against the shore, and the moonlight was dancing across the water in a way that made me"
            }
        }
    }

    /// The currently selected context preset in the picker.
    /// Does NOT auto-populate — call `loadContextPreset()` to apply it.
    @Published var selectedContextPreset: ContextPreset? = nil

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
    @Published var temperature: Double = ModelOption.defaultTemperature
    @Published var topP: Double = ModelOption.defaultTopP
    @Published var repeatPenalty: Double = ModelOption.defaultRepeatPenalty
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

    // MARK: Backspace Correction

    /// The previous draft text value, used to detect backspace patterns for correction.
    private var previousDraftText: String = ""

    /// The original (misspelled) word before the user started backspacing into it.
    /// Captured once when the user first backspaces into a word boundary.
    /// Updated when the user backspaces into a *different* earlier word.
    private var correctionCandidateWord: String?

    /// The list of word-boundary counts where candidates were captured.
    /// Used to detect when the user has backspaced into a new word.
    private var correctionCapturedWordCount: Int = -1

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

        // === Wire model/backend/appState changes to controller ===
        // When the user changes the model (via Settings or menu bar), push it
        // to the controller immediately so the next prediction uses the new model.
        appState.$selectedModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Clear stale suggestion from the old model
                self.suggestion = ""
                self.controller.cancelPrediction()
                self.updateControllerFromAppState()
                // Re-trigger a prediction for the current draft with the new model
                if self.isEnabled && !self.draftText.isEmpty {
                    self.controller.editorStateChanged(EditorState(
                        textBeforeCursor: self.draftText,
                        textAfterCursor: ""
                    ))
                }
                print("🔄 Model changed to: \(self.effectiveModelOption.displayName)")
            }
            .store(in: &cancellables)

        // When the user changes the backend, update the controller's LLMClient
        // so subsequent predictions hit the correct API endpoint.
        appState.$selectedBackend
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.suggestion = ""
                self.controller.cancelPrediction()
                self.controller.updateConfig(self.appState.config)
                self.updateControllerFromAppState()
                print("🔄 Backend changed to: \(self.appState.selectedBackend.displayName)")
            }
            .store(in: &cancellables)

        // When the underlying config changes (e.g. base URL), push to controller.
        appState.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                guard let self else { return }
                self.suggestion = ""
                self.controller.cancelPrediction()
                self.controller.updateConfig(newConfig)
                self.updateControllerFromAppState()
            }
            .store(in: &cancellables)

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

        // Wire correction detection: when a suggestion arrives and we have
        // a correction candidate, check if the prediction's first complete word
        // (after stripping stylistic prefixes like "...") differs from the
        // original candidate word.
        //
        // The model often outputs "...tely" as a continuation suffix rather than
        // the full word "absolutely". We strip leading punctuation/ellipsis and
        // extract the first real word, then see if it completes the partial text
        // into something different from the original candidate.
        controller.$suggestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSuggestion in
                guard let self, let candidate = self.correctionCandidateWord else { return }
                guard !newSuggestion.isEmpty else { return }

                // Strip leading ellipsis/punctuation from the suggestion
                // e.g. "...tely impressed" → "tely impressed"
                let cleaned = newSuggestion.trimmingCharacters(in: CharacterSet(charactersIn: ".…—–-"))

                // Get the first real word from the cleaned suggestion
                let firstWord = cleaned
                    .split(separator: " ")
                    .first
                    .flatMap(String.init) ?? cleaned

                // The partial text the user has typed so far
                let partialText = self.draftText.split(separator: " ").last.flatMap(String.init) ?? ""

                // Check: does the first predicted word complete the partial text
                // into something different from the original candidate?
                // e.g. partialText="absolutt", firstWord="tely", combined="absolutely"
                // vs candidate="absolutley"
                guard !firstWord.isEmpty, !partialText.isEmpty else { return }

                // Skip if the first word starts with uppercase — that means the model
                // is starting a new sentence, not completing the current partial word.
                guard let firstChar = firstWord.first, !firstChar.isUppercase else { return }

                let combinedWord = partialText + firstWord

                // Only show correction if:
                // 1. The combined word differs from the captured candidate
                // 2. The combined word is longer than the partial text (it's a completion)
                // 3. The combined word starts with the partial text (it's truly a completion)
                // 4. The first word characters are not too long (avoid matching multi-word continuations)
                if combinedWord != candidate,
                   combinedWord.count > partialText.count,
                   combinedWord.hasPrefix(partialText),
                   firstWord.count <= partialText.count + 4 {  // The suffix shouldn't be longer than the partial word itself by much
                    self.correctionState = CorrectionState(
                        originalWord: candidate,
                        suggestedCorrection: combinedWord
                    )
                    print("BC: '\(candidate)'→'\(combinedWord)' (partial='\(partialText)'+first='\(firstWord)')")
                }
            }
            .store(in: &cancellables)

        loadSettings()
        // Push initial params to controller
        updateControllerFromAppState()

        // Auto-start when the app launches
        isEnabled = true
    }

    // MARK: Draft Handling

    private func handleDraftChanged() {
        guard isEnabled, !isAccepting else { return }

        // Detect backspace correction pattern: text got shorter.
        if draftText.count < previousDraftText.count {
            let prevWords = previousDraftText.split(separator: " ")
            let curWords = draftText.split(separator: " ")

            // Determine if user is backspacing into the last word:
            // - Same word count but no trailing space = trimming a word
            // - Fewer words = deleted whitespace, now on a different word
            let isBackspacingIntoWord = !draftText.hasSuffix(" ")

            if isBackspacingIntoWord, let prevLast = prevWords.last.flatMap(String.init) {
                let curWordCount = curWords.count

                if correctionCandidateWord == nil {
                    // First capture — the previous text's last word is the candidate
                    correctionCandidateWord = prevLast
                    correctionCapturedWordCount = prevWords.count
                    print("BC: candidate='\(prevLast)' words=\(prevWords.count)")
                } else if prevWords.count < correctionCapturedWordCount {
                    // User has backspaced across a word boundary into an earlier word
                    // Update the candidate to the new current word
                    correctionCandidateWord = prevLast
                    correctionCapturedWordCount = prevWords.count
                    correctionState = nil
                    print("BC: updated candidate='\(prevLast)' words=\(prevWords.count)")
                } else if prevWords.count == curWordCount, curWordCount < correctionCapturedWordCount {
                    // Still deleting within the same word boundary, but we crossed into
                    // a word that was from a different position
                    correctionCandidateWord = prevLast
                    correctionCapturedWordCount = prevWords.count
                    correctionState = nil
                    print("BC: updated candidate='\(prevLast)' words=\(prevWords.count)")
                }
            } else if isBackspacingIntoWord, prevWords.count > curWords.count {
                // Deleted a space but not yet typing characters — clear
                correctionCandidateWord = nil
                correctionState = nil
                correctionCapturedWordCount = -1
            } else {
                // Normal backspace (removing space between words) — clear state
                correctionCandidateWord = nil
                correctionState = nil
                correctionCapturedWordCount = -1
            }
        } else if draftText.count > previousDraftText.count {
            // Typing forward — clear correction state
            correctionCandidateWord = nil
            correctionState = nil
            correctionCapturedWordCount = -1
        }

        previousDraftText = draftText
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
        //
        // Also handles backspace correction Tab/ESC when correction state is active.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEnabled else { return event }

            // Correction state takes priority: Tab accepts, ESC rejects
            if self.correctionState != nil {
                if event.keyCode == 48 { // kVK_Tab
                    self.acceptCorrection()
                    return nil
                }
                if event.keyCode == 53 { // kVK_Escape
                    self.rejectCorrection()
                    return nil
                }
                // Continued typing dismisses correction (handled in handleDraftChanged)
                return event
            }

            // Normal prediction acceptance
            if !self.suggestion.isEmpty, event.keyCode == 48 {
                self.acceptWord()
                return nil
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

    /// Applies the currently selected context preset to the playground text field.
    func loadContextPreset() {
        guard let preset = selectedContextPreset else { return }
        draftText = preset.text
    }

    // MARK: Actions

    func acceptSuggestion() {
        guard !suggestion.isEmpty else { return }

        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = draftText + trimmed + " "
        isAccepting = true
        draftText = newText
        isAccepting = false
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

    // MARK: Correction Actions

    /// Accepts the backspace correction: replaces the partial last word with the
    /// suggested correction, then continues prediction from the corrected text.
    func acceptCorrection() {
        guard let correction = correctionState else { return }

        // Replace the partial last word with the correction
        let words = draftText.split(separator: " ")
        guard !words.isEmpty else { return }

        let partialLast = String(words.last!)
        let prefix = words.dropLast().joined(separator: " ")
        let correctedText = prefix.isEmpty
            ? correction.suggestedCorrection + " "
            : prefix + " " + correction.suggestedCorrection + " "

        isAccepting = true
        draftText = correctedText
        isAccepting = false

        correctionCandidateWord = nil
        correctionState = nil
        suggestion = ""

        print("Correction accepted: \(correction.originalWord) → \(correction.suggestedCorrection)")
    }

    /// Rejects the backspace correction: removes the correction UI and returns
    /// to normal prediction state.
    func rejectCorrection() {
        correctionCandidateWord = nil
        correctionState = nil
        print("Correction rejected")
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
        controller.repeatPenalty = repeatPenalty
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
        temperature = settings.inference.temperature > 0 ? settings.inference.temperature : ModelOption.defaultTemperature
        topP = settings.inference.topP
        repeatPenalty = settings.inference.repeatPenalty > 0 ? settings.inference.repeatPenalty : ModelOption.defaultRepeatPenalty
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