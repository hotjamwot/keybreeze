import Foundation
import OSLog
import Combine

/// Prediction orchestrator with latency tracking, PromptBuilder integration,
/// and prediction history recording.
@MainActor
final class CompletionController: ObservableObject {
    // MARK: Published State

    @Published var isRunning = false
    @Published var suggestion = ""
    @Published var statusMessage = "Ready"
    @Published var currentMode: PredictionMode?
    @Published var currentLatency: TimeInterval?
    @Published var currentTTFT: TimeInterval?

    // MARK: Private

    private var client: LLMClient
    private var config: LLMConfig
    private var activeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let debounceDelay: Duration = .milliseconds(45)
    private var editorState: EditorState = .init(textBeforeCursor: "", textAfterCursor: "")

    /// The model to use for predictions — updated from AppState.
    /// Defaults sourced from ModelOption (single source of truth).
    var modelID: String = "gemma2:2b"
    var temperature: Double = ModelOption.defaultTemperature
    var topP: Double = ModelOption.defaultTopP
    var repeatPenalty: Double = ModelOption.defaultRepeatPenalty
    var maxWords: Int = 5
    var customSystemPrompt: String = ""
    var styleNudge: String = ""

    /// Current app context — set by SystemWidePredictor before triggering predictions.
    /// Used for per-app prompt gating and custom instructions.
    var currentAppName: String = ""
    var currentAppBundleID: String = ""

    /// Callback for recording prediction results in history
    var onRecordPrediction: ((PredictionRecord) -> Void)?

    /// Lightweight acceptance echo tracking: when the user accepts a suggestion
    /// and the text field echoes back the accepted text, we skip redundant
    /// re-completions until the user diverges.
    var expectedTextAfterAcceptance: String = ""

    // Timing for current prediction
    private var predictionStartTime: Date?
    private var firstTokenTime: Date?

    // MARK: Init

    init(config: LLMConfig) {
        self.config = config
        self.client = LLMClient(config: config)
    }

    /// Update the underlying config (e.g., when backend changes).
    /// Recreates the LLMClient so the new API base URL takes effect.
    func updateConfig(_ newConfig: LLMConfig) {
        config = newConfig
        cancelAll()
        client = LLMClient(config: newConfig)
    }

    // MARK: Public API

    /// Cancels any in-flight prediction and debounce task.
    func cancelPrediction() {
        cancelAll()
    }

    func editorStateChanged(_ state: EditorState) {
        guard isRunning else { return }
        cancelAll()
        editorState = state

        // If the new state matches our expected acceptance echo, skip
        // prediction — the user is just settling after accepting a suggestion.
        if !expectedTextAfterAcceptance.isEmpty,
           state.textBeforeCursor == expectedTextAfterAcceptance ||
           state.textBeforeCursor.hasPrefix(expectedTextAfterAcceptance) {
            suggestion = ""
            return
        }
        // If the user has diverged from expected text, clear the expectation
        // and proceed normally.
        if !expectedTextAfterAcceptance.isEmpty &&
           !state.textBeforeCursor.hasPrefix(expectedTextAfterAcceptance) {
            expectedTextAfterAcceptance = ""
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounceDelay)
                await self?.runPrediction(state: state)
            } catch { /* cancelled */ }
        }
    }

    func start() {
        isRunning = true
        expectedTextAfterAcceptance = ""
        statusMessage = "Predicting Engine Standing By"
    }

    func stop() {
        cancelAll()
        isRunning = false
        suggestion = ""
        currentLatency = nil
        currentTTFT = nil
        expectedTextAfterAcceptance = ""
    }

    // MARK: Private

    private func runPrediction(state: EditorState) {
        guard readinessCheck() else { return }
        guard !state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            suggestion = ""
            return
        }

        cancelAll()
        currentMode = detectMode(from: state)
        statusMessage = "Predicting..."

        let context = trimContext(state.textBeforeCursor, maxChars: 800)
        let isRaw = config.backend == .llamaCpp
        let systemPrompt = PromptBuilder.systemPrompt(
            customPrompt: customSystemPrompt,
            styleNudge: styleNudge
        )

        // Resolve per-app custom instructions from AppCompatibility
        let appCustomInstructions = AppCompatibility.customPromptSuffix(for: currentAppBundleID)

        let prompt = PromptBuilder.continuationPrompt(
            context: context,
            textAfterCursor: state.textAfterCursor,
            styleNudge: styleNudge,
            maxWords: maxWords,
            raw: isRaw,
            systemPromptOverride: isRaw ? systemPrompt : nil,
            appName: currentAppName,
            bundleIdentifier: currentAppBundleID,
            customInstructions: appCustomInstructions
        )

        // Reset timing — capture start time locally for Sendable closure safety
        let predictionStartTime = Date()
        self.predictionStartTime = predictionStartTime
        self.firstTokenTime = nil
        self.currentLatency = nil
        self.currentTTFT = nil

        // State captured for the completion callback
        let capturedContext = state.textBeforeCursor
        let capturedAfterCursor = state.textAfterCursor
        let capturedMode = currentMode?.rawValue ?? ""
        let capturedMaxWords = maxWords

        activeTask = Task { [weak self] in
            guard let self else { return }
            let model = self.modelID
            let temp = self.temperature
            let tp = self.topP
            let rp = self.repeatPenalty
            let maxWords = self.maxWords

            // Local timing variables (not actor-isolated, hoisted for catch block access)
            var localFirstTokenTime: Date?
            var accumulatedTokens = ""
            var ttft: TimeInterval?

            do {
                try await client.streamCompletion(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    model: model,
                    maxTokens: min(maxWords * 4, 64),
                    temperature: temp,
                    topP: tp,
                    repeatPenalty: rp,
                    onToken: { token in
                        let now = Date()
                        // Track first token (local var is safe)
                        if localFirstTokenTime == nil {
                            localFirstTokenTime = now
                            ttft = now.timeIntervalSince(predictionStartTime)
                            Task { @MainActor in
                                self.currentTTFT = ttft
                            }
                        }
                        let wasEmpty = accumulatedTokens.isEmpty
                        accumulatedTokens += token
                        // Streaming threshold gating (§10): only update the visible suggestion
                        // once we've accumulated meaningful content. The gating strategy
                        // depends on whether the user is mid-word or between words:
                        //
                        // - Mid-word (draft ends without a trailing space):
                        //   Show tokens immediately — the model is completing the current
                        //   word (e.g. "conversa" → "tion") so every token is relevant
                        //   and there's no "dancing" to suppress.
                        //
                        // - Between words (draft ends with a trailing space):
                        //   Wait until we have a full word (contains a space) or at least
                        //   10 characters before showing. This prevents flickering
                        //   partial-word tokens like "I'" → "I'm" → "I'm doing".
                        // Apply post-generation filtering before displaying.
                        // This strips multi-line output, garbage chars, and duplicates.
                        let draftEndsMidWord = !capturedContext.hasSuffix(" ")
                        if wasEmpty || draftEndsMidWord {
                            if let filtered = CompletionController.filterSuggestion(
                                accumulatedTokens,
                                contextBeforeCursor: capturedContext,
                                contextAfterCursor: capturedAfterCursor,
                                maxWords: capturedMaxWords
                            ) {
                                Task { @MainActor in
                                    self.suggestion = filtered
                                }
                            }
                        } else {
                            let hasFullWord = accumulatedTokens.contains(" ")
                            let hasEnoughChars = accumulatedTokens.count >= 10
                            if hasFullWord || hasEnoughChars {
                                if let filtered = CompletionController.filterSuggestion(
                                    accumulatedTokens,
                                    contextBeforeCursor: capturedContext,
                                    contextAfterCursor: capturedAfterCursor,
                                    maxWords: capturedMaxWords
                                ) {
                                    Task { @MainActor in
                                        self.suggestion = filtered
                                    }
                                }
                            }
                        }
                    }
                )

                // Prediction completed (stream ended normally)
                let totalTime = Date().timeIntervalSince(predictionStartTime)
                let finalTTFT = ttft ?? totalTime

                Task { @MainActor in
                    self.currentLatency = totalTime
                    self.statusMessage = "Ready"
                    self.recordPrediction(
                        text: capturedContext,
                        continuation: accumulatedTokens,
                        mode: capturedMode,
                        ttft: finalTTFT,
                        totalTime: totalTime,
                        resolution: .ignored
                    )
                }
            } catch {
                if Task.isCancelled {
                    // Cancellation — record as cancelled if we had started generating
                    let totalTime = Date().timeIntervalSince(predictionStartTime)
                    Task { @MainActor in
                        if !accumulatedTokens.isEmpty {
                            self.recordPrediction(
                                text: capturedContext,
                                continuation: accumulatedTokens,
                                mode: capturedMode,
                                ttft: ttft ?? 0,
                                totalTime: totalTime,
                                resolution: .cancelled
                            )
                        }
                    }
                }
            }
        }
    }

    private func recordPrediction(
        text: String,
        continuation: String,
        mode: String,
        ttft: TimeInterval,
        totalTime: TimeInterval,
        resolution: PredictionResolution
    ) {
        let record = PredictionRecord(
            timestamp: Date(),
            modelDisplayName: modelID,
            mode: mode,
            resolution: resolution,
            timeToFirstToken: ttft > 0 ? ttft : nil,
            totalTime: totalTime,
            typedContext: text,
            generatedContinuation: continuation
        )
        onRecordPrediction?(record)

        KeybreezeLatencyLogger.log(
            backend: config.backend.displayName,
            modelDisplayName: modelID,
            ollamaModelId: modelID,
            verbosityBias: 0,
            timeToFirstToken: ttft,
            totalTime: totalTime,
            continuation: continuation,
            wordCount: wordCount(in: continuation),
            wasGated: true,
            draftEndedMidWord: !text.hasSuffix(" ")
        )
    }

    private func detectMode(from state: EditorState) -> PredictionMode {
        let text = state.textBeforeCursor
        guard let last = text.unicodeScalars.last else { return .midType }

        if CharacterSet.whitespacesAndNewlines.contains(last) {
            return .pause
        }
        return .midType
    }

    private func trimContext(_ text: String, maxChars: Int) -> String {
        let startIdx = max(0, text.count - maxChars)
        guard startIdx > 0 else { return text }
        let idx = text.index(text.startIndex, offsetBy: startIdx)
        return String(text[idx...])
    }

    private func readinessCheck() -> Bool {
        true // Simplified - no IME check for now
    }

    private func cancelAll() {
        client.cancel()
        activeTask?.cancel()
        activeTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func wordCount(in text: String) -> Int {
        text.split(separator: " ").filter { !$0.isEmpty }.count
    }

    // MARK: - Post-Generation Filtering (Tier 2)

    /// Filters a raw suggestion string, returning a cleaned version or nil
    /// if the suggestion should be suppressed entirely.
    ///
    /// Applied in the streaming gate before updating `self.suggestion`.
    /// Addresses: multi-line predictions, garbage characters, excessive length,
    /// and duplication of after-cursor text.
    nonisolated static func filterSuggestion(
        _ raw: String,
        contextBeforeCursor: String,
        contextAfterCursor: String,
        maxWords: Int
    ) -> String? {
        var text = raw

        // 1. Multi-line: truncate at the first newline.
        //    The model sometimes generates newlines as hesitation tokens.
        //    No \n stop token means these leak into the output.
        if let newlineIdx = text.firstIndex(of: "\n") {
            text = String(text[..<newlineIdx])
        }

        // 2. Garbage character filter: strip non-printable characters,
        //    HTML tags, and control sequences.
        text = text.filter { char in
            // Allow normal printable ASCII, extended Latin, and whitespace
            let scalar = char.unicodeScalars.first!
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
            if scalar.value >= 32 && scalar.value < 127 { return true } // Standard printable
            if scalar.value >= 128 { return true } // Extended Unicode (accents, etc.)
            return false // Control characters
        }

        // Strip HTML tags (model sometimes outputs <br>, <p>, etc.)
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // 3. Empty after filtering
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 4. Word count guard: reject if prediction is excessively long
        let words = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if words.count > maxWords * 3 {
            // Prediction is wildly too long — likely a generation runaway
            return nil
        }

        // 5. Duplicate after-cursor: if the suggestion starts with text that
        //    appears immediately after the cursor, strip the duplicate prefix.
        if !contextAfterCursor.isEmpty {
            let afterTrimmed = contextAfterCursor.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(afterTrimmed) {
                let remaining = String(trimmed.dropFirst(afterTrimmed.count))
                    .trimmingCharacters(in: .whitespaces)
                if remaining.isEmpty { return nil }
                text = remaining
            }
        }

        // 6. Starts with punctuation/dashes/ellipsis: likely garbage
        let firstChar = text.trimmingCharacters(in: .whitespaces).first
        if let firstChar {
            if firstChar == "." || firstChar == "…" || firstChar == "—" || firstChar == "-" {
                // Allow single dash if it's part of a word (e.g., "-wise")
                let trimmedText = text.trimmingCharacters(in: .whitespaces)
                if trimmedText.hasPrefix("...") || trimmedText.hasPrefix("…") || trimmedText.hasPrefix("—") {
                    return nil
                }
            }
        }

        // 7. Pure numbers / numeric garbage: reject continuations that are
        //    mostly digits (model often defaults to numbers like "2", "100%", etc.)
        let trimmedForNumeric = text.trimmingCharacters(in: .whitespaces)
        let digitCount = trimmedForNumeric.filter { $0.isNumber }.count
        let alphaCount = trimmedForNumeric.filter { $0.isLetter }.count
        // If it's purely digits (e.g., "2", "100")
        if digitCount == trimmedForNumeric.count && trimmedForNumeric.count <= 6 {
            return nil
        }
        // If digits dominate and it's short (e.g., "100%", "19-year")
        if trimmedForNumeric.count <= 8 && digitCount > alphaCount {
            return nil
        }
        // Patterns like "19-year-old", "6'4″" — numbers mixed with separators
        if trimmedForNumeric.count <= 12 && digitCount >= 2 && alphaCount <= 2 {
            return nil
        }

        // 8. Very short single-word continuations that are likely wrong
        let trimmedWords = trimmedForNumeric.split(separator: " ").filter { !$0.isEmpty }
        if trimmedWords.count == 1, let word = trimmedWords.first {
            let wordStr = String(word)
            // Single character or single digit — too noisy to be useful
            if wordStr.count <= 1 { return nil }
            // Single word that's all punctuation/symbols
            if wordStr.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return nil }
        }

        return text.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Supporting Types

struct EditorState {
    let textBeforeCursor: String
    let textAfterCursor: String
}