import Foundation

/// Console-only latency helper for engine tuning (TTFT, total wall time, word count).
/// Logs are deliberately verbose so copy-paste diagnostics tell the full story.
enum KeybreezeLatencyLogger {
    static func log(
        backend: String,
        modelDisplayName: String,
        ollamaModelId: String,
        verbosityBias: Double,
        timeToFirstToken: TimeInterval?,
        totalTime: TimeInterval,
        continuation: String,
        wordCount: Int,
        wasGated: Bool,
        draftEndedMidWord: Bool
    ) {
        let ttft: String
        if let timeToFirstToken {
            ttft = formatSeconds(timeToFirstToken)
        } else {
            ttft = "n/a"
        }
        let gating = wasGated
            ? (draftEndedMidWord ? "mid-word (shown immediately)" : "between-words (gate re-evaluated)")
            : "none (first token)"
        let continuationPreview = continuation.isEmpty
            ? "(empty)"
            : continuation.trimmingCharacters(in: .whitespacesAndNewlines)
        print(
            """
            [KeybreezeLatency]
            backend: \(backend) | model: \(modelDisplayName) (\(ollamaModelId))
            verbosityBias: \(formatDouble(verbosityBias))
            timeToFirstToken: \(ttft) | totalTime: \(formatSeconds(totalTime))
            continuations: [\(continuationPreview)]
            wordCount: \(wordCount)
            gating: \(gating)
            """
        )
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.3fs", value)
    }

    private static func formatDouble(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}