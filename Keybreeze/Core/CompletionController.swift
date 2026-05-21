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

    private let client: LLMClient
    private var config: LLMConfig
    private var activeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let debounceDelay: Duration = .milliseconds(45)
    private var editorState: EditorState = .init(textBeforeCursor: "", textAfterCursor: "")

    /// The model to use for predictions — updated from AppState.
    var modelID: String = "gemma2:2b"
    var temperature: Double = 0.35
    var topP: Double = 0.85
    var maxWords: Int = 5
    var customSystemPrompt: String = ""
    var styleNudge: String = ""

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

    // MARK: Public API

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
        let prompt = PromptBuilder.continuationPrompt(
            context: context,
            styleNudge: styleNudge,
            maxWords: maxWords
        )
        let systemPrompt = PromptBuilder.systemPrompt(
            customPrompt: customSystemPrompt,
            styleNudge: styleNudge
        )

        // Reset timing — capture start time locally for Sendable closure safety
        let predictionStartTime = Date()
        self.predictionStartTime = predictionStartTime
        self.firstTokenTime = nil
        self.currentLatency = nil
        self.currentTTFT = nil

        // State captured for the completion callback
        let capturedContext = state.textBeforeCursor
        let capturedMode = currentMode?.rawValue ?? ""

        activeTask = Task { [weak self] in
            guard let self else { return }
            let model = self.modelID
            let temp = self.temperature
            let tp = self.topP
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
                        accumulatedTokens += token
                        Task { @MainActor in
                            self.suggestion = accumulatedTokens
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
            modelDisplayName: modelID,
            ollamaModelId: modelID,
            verbosityBias: 0,
            timeToFirstToken: ttft,
            totalTime: totalTime,
            wordCount: wordCount(in: continuation)
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
}

// MARK: - Supporting Types

struct EditorState {
    let textBeforeCursor: String
    let textAfterCursor: String
}