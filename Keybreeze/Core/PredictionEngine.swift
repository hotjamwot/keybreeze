import Foundation
import OSLog

/// Runs a single cancellable prediction stream. UI-agnostic; callers observe `currentSuggestion`.
@MainActor
final class PredictionEngine {
    private(set) var currentSuggestion: String = ""
    private(set) var isRunning: Bool = false

    /// Metrics from the last completed prediction run, used by history recording.
    private(set) var lastRunMetrics: (ttft: TimeInterval?, totalTime: TimeInterval, cancelled: Bool)?

private let provider: any LLMProvider
private let backend: LLMBackend
private let configuration: LLMConfiguration
private let log = Logger(subsystem: "app.keybreeze", category: "prediction-engine")

private var activeTask: Task<Void, Never>?
private var suppressStreamUpdates = false
private var latencyRequestStart: Date?
private var latencyFirstToken: Date?
private var latencyModelSnapshot: ModelOption?

init(
    backend: LLMBackend,
    configuration: LLMConfiguration
) {
    self.backend = backend
    self.configuration = configuration
    self.provider = backend.makeProvider(configuration: configuration)
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
        styleNudge: String = ""
    ) {
        cancel()

        let maxWords = mode.maxWords(modelCap: model.maxWords)
        let focused = ContextBuilder.focusedState(from: editorState)
        let prompt = PromptBuilder.continuationPrompt(
            for: focused,
            modelOption: model,
            customSystemPrompt: customSystemPrompt,
            styleNudge: styleNudge
        )

        currentSuggestion = ""
        suppressStreamUpdates = false
        isRunning = true

        if logLatency {
            latencyRequestStart = Date()
            latencyFirstToken = nil
            latencyModelSnapshot = model
        }

        log.info("Predict mode=\(mode.rawValue, privacy: .public) backend=\(self.backend.rawValue, privacy: .public) model=\(model.ollamaId, privacy: .public)")

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.provider.streamCompletion(prompt: prompt, model: model.ollamaId) { token in
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
                    self.discardLatencyTracking()
                    self.isRunning = false
                    self.activeTask = nil
                    self.log.error("Predict failed mode=\(mode.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
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

    private func appendTokenRespectingWordCap(_ token: String, maxWords: Int, onToken: ((String) -> Void)?) {
        guard !suppressStreamUpdates else { return }
        let proposed = currentSuggestion + token
        if WordLimiter.wordCount(in: proposed) <= maxWords {
            currentSuggestion = proposed
            onToken?(token)
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
