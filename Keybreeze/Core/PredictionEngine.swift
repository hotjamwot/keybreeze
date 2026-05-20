import Foundation
import OSLog

/// Runs a single cancellable prediction stream. UI-agnostic; callers observe `currentSuggestion`.
@MainActor
final class PredictionEngine {
    private(set) var currentSuggestion: String = ""
    private(set) var isRunning: Bool = false

    /// Metrics from the last completed prediction run, used by history recording.
    private(set) var lastRunMetrics: (ttft: TimeInterval?, totalTime: TimeInterval, cancelled: Bool)?
    /// Callback invoked when a prediction fails with a non-cancellation error.
    var onPredictionError: ((String) -> Void)?

private let provider: any LLMProvider
private let config: LLMConfig
private let log = Logger(subsystem: "app.keybreeze", category: "prediction-engine")

private var activeTask: Task<Void, Never>?
private var suppressStreamUpdates = false
private var latencyRequestStart: Date?
private var latencyFirstToken: Date?
private var latencyModelSnapshot: ModelOption?
/// Tracks whether the prediction was launched for a mid-word context.
/// Used to adjust word-counting behavior during token accumulation.
private var isMidWordPrediction: Bool = false

init(config: LLMConfig) {
    self.config = config
    self.provider = Self.makeProvider(config: config)
}

/// Creates the appropriate provider for a given backend.
private static func makeProvider(config: LLMConfig) -> any LLMProvider {
    switch config.backend {
    case .ollama:
        return OllamaLLMService(config: config)
    case .llamaCpp:
        return LlamaCppService(config: config)
    }
}

    func clearSuggestion() {
        currentSuggestion = ""
    }

    func cancel() {
        provider.cancel()
        activeTask?.cancel()
        activeTask = nil
        suppressStreamUpdates = true
        isRunning = false
    }

    /// Starts a new prediction, cancelling any in-flight stream.
    /// - Parameters:
    ///   - customSystemPrompt: If non-empty, passed to PromptBuilder to override system-level framing.
    ///   - customContinuationPrompt: If non-empty, passed to PromptBuilder to replace the entire prompt template.
    func predict(
        editorState: EditorState,
        model: ModelOption,
        mode: PredictionMode,
        logLatency: Bool = true,
        onToken: ((String) -> Void)? = nil,
        customSystemPrompt: String = "",
        styleNudge: String = "",
        midTypeWords: Int = 0,
        pauseWords: Int = 0
    ) {
        cancel()

        let maxWords = mode.maxWords(midTypeWords: midTypeWords, pauseWords: pauseWords, modelCap: model.maxWords)
        let focused = ContextBuilder.focusedState(from: editorState)
        let prompt = PromptBuilder.continuationPrompt(
            for: focused,
            modelOption: model,
            customSystemPrompt: customSystemPrompt,
            styleNudge: styleNudge,
            midTypeWords: midTypeWords,
            pauseWords: pauseWords,
            mode: mode
        )

        // Detect if the editor text ends mid-word (no trailing whitespace/punctuation)
        let trimmed = editorState.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        isMidWordPrediction = Self.isEndingMidWord(trimmed)

        currentSuggestion = ""
        suppressStreamUpdates = false
        isRunning = true

        if logLatency {
            latencyRequestStart = Date()
            latencyFirstToken = nil
            latencyModelSnapshot = model
        }

        log.info("Predict mode=\(mode.rawValue, privacy: .public) backend=\(self.config.backend.rawValue, privacy: .public) model=\(model.ollamaId, privacy: .public) midWord=\(self.isMidWordPrediction)")

         activeTask = Task { [weak self] in
             guard let self else { return }
             do {
                  try await self.provider.streamCompletion(prompt: prompt, model: model.ollamaId, modelOption: model, maxWords: maxWords) { token in
                     Task { @MainActor [weak self] in
                         guard let self else { return }
                         guard !self.suppressStreamUpdates else { return }
                         if self.latencyFirstToken == nil {
                             self.latencyFirstToken = Date()
                         }
                         self.appendTokenRespectingWordCap(token, maxWords: maxWords, onToken: onToken)
                     }
                 }
                 await MainActor.run { [weak self] in
                     guard let self else { return }
                     self.finishRun(logLatency: logLatency, mode: mode)
                 }
             } catch is CancellationError {
                 await MainActor.run { [weak self] in
                     guard let self else { return }
                     self.finishRun(logLatency: logLatency, mode: mode, cancelled: true)
                 }
             } catch {
                 await MainActor.run { [weak self] in
                     guard let self else { return }
                     if Self.isBenignCancellation(error) {
                         self.finishRun(logLatency: logLatency, mode: mode, cancelled: true)
                         return
                     }
                     // Surface the error to the scheduler for user-visible diagnostics
                     let errorMsg = "\(String(describing: error))"
                     self.discardLatencyTracking()
                     self.isRunning = false
                     self.activeTask = nil
                     self.log.error("Predict failed mode=\(mode.rawValue, privacy: .public): \(errorMsg, privacy: .public)")
                     self.onPredictionError?(errorMsg)
                 }
             }
         }
    }

    /// Returns true if the given text ends mid-word (no trailing whitespace and last char is not punctuation).
    private static func isEndingMidWord(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters)
        return !terminators.contains(last)
    }

    private static func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private func discardLatencyTracking() {
        latencyRequestStart = nil
        latencyFirstToken = nil
        latencyModelSnapshot = nil
    }

    private func finishRun(logLatency: Bool, mode: PredictionMode, cancelled: Bool = false) {
        // Capture metrics before discarding
        let total: TimeInterval
        let ttft: TimeInterval?
        if let start = latencyRequestStart {
            total = Date().timeIntervalSince(start)
            ttft = latencyFirstToken.map { $0.timeIntervalSince(start) }
        } else {
            total = 0
            ttft = nil
        }
        lastRunMetrics = (ttft, total, cancelled)

        if logLatency, ttft != nil {
            logLatencyIfNeeded(mode: mode)
        } else {
            discardLatencyTracking()
        }
        if isRunning {
            isRunning = false
        }
        activeTask = nil
        if cancelled {
            log.debug("Predict cancelled mode=\(mode.rawValue, privacy: .public)")
        } else {
            log.info("Predict finished mode=\(mode.rawValue, privacy: .public): \(self.currentSuggestion, privacy: .public)")
        }
    }

    private func logLatencyIfNeeded(mode: PredictionMode? = nil) {
        guard let start = latencyRequestStart else { return }
        let snapshot = latencyModelSnapshot
        let total = Date().timeIntervalSince(start)
        let ttft = latencyFirstToken.map { $0.timeIntervalSince(start) }
        let words = WordLimiter.wordCount(in: currentSuggestion)
        if let snapshot {
            KeybreezeLatencyLogger.log(
                modelDisplayName: snapshot.displayName,
                ollamaModelId: snapshot.ollamaId,
                verbosityBias: snapshot.verbosityBias,
                timeToFirstToken: ttft,
                totalTime: total,
                wordCount: words
            )
        }
        if let mode {
            log.debug("[KeybreezePrediction] mode=\(mode.rawValue, privacy: .public) words=\(words)")
        }
        discardLatencyTracking()
    }

    /// Strips leading tokens that are nothing but punctuation (ellipsis, periods, etc.)
    /// to prevent grammar errors like continuations starting with "." or "..."
    /// For mid-word completions, is more lenient — allows apostrophe-prefixed tokens like "'s".
    private func sanitizeToken(_ token: String) -> String? {
        // Always allow tokens that contain non-punctuation characters
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // If the token has any word characters, always allow it
        let hasWordChars = trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        if hasWordChars { return token }
        
        // For purely punctuation tokens:
        // If we already have a suggestion, allow punctuation continuation
        // (e.g. the model adding "." at the end)
        if !currentSuggestion.isEmpty { return token }
        
        // If we're in a mid-word prediction, allow punctuation tokens
        // (e.g. "'s" to complete "John" → "John's")
        if isMidWordPrediction { return token }
        
        // Otherwise, skip leading punctuation-only tokens to prevent
        // the model from starting with "." or "..."
        return nil
    }

    private func appendTokenRespectingWordCap(_ token: String, maxWords: Int, onToken: ((String) -> Void)?) {
        guard !suppressStreamUpdates else { return }
        
        // Sanitize the token before appending
        guard let sanitized = sanitizeToken(token) else { return }
        
        let proposed = currentSuggestion + sanitized
        
        // For mid-word predictions, the completion is completing the current partial word.
        // Count words in the proposed completion (the partial word + completion).
        // The partial word itself should not count against the word cap since the user
        // already typed it — we only need to count any additional words the model adds.
        if isMidWordPrediction {
            // The model is completing a partial word. The full result (partial + completion)
            // counts as at most 1 word for the completed word plus any extra words.
            let wordCount = WordLimiter.wordCount(in: proposed)
            if wordCount <= maxWords {
                currentSuggestion = proposed
                onToken?(sanitized)
                return
            }
            
            // If we exceed the word cap, truncate to the max words
            let capped = WordLimiter.truncateToMaxWords(proposed, maxWords: maxWords)
            let suffix = String(capped.dropFirst(currentSuggestion.count))
            if !suffix.isEmpty {
                currentSuggestion = capped
                onToken?(suffix)
            }
            suppressStreamUpdates = true
            provider.cancel()
            isRunning = false
            return
        }
        
        // Normal (non-mid-word) handling
        if WordLimiter.wordCount(in: proposed) <= maxWords {
            currentSuggestion = proposed
            onToken?(sanitized)
            return
        }
        let capped = WordLimiter.truncateToMaxWords(proposed, maxWords: maxWords)
        let suffix = String(capped.dropFirst(currentSuggestion.count))
        currentSuggestion = capped
        if !suffix.isEmpty {
            onToken?(suffix)
        }
        suppressStreamUpdates = true
        provider.cancel()
        isRunning = false
    }
}