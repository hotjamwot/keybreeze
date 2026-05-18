import Foundation

/// Console-only latency helper for engine tuning (TTFT, total wall time, word count).
enum KeybreezeLatencyLogger {
    static func log(
        modelDisplayName: String,
        ollamaModelId: String,
        verbosityBias: Double,
        timeToFirstToken: TimeInterval?,
        totalTime: TimeInterval,
        wordCount: Int
    ) {
        let ttft: String
        if let timeToFirstToken {
            ttft = formatSeconds(timeToFirstToken)
        } else {
            ttft = "n/a"
        }
        print(
            """
            [KeybreezeLatency]
            model: \(modelDisplayName) (\(ollamaModelId))
            verbosityBias: \(formatDouble(verbosityBias))
            timeToFirstToken: \(ttft)
            totalTime: \(formatSeconds(totalTime))
            wordCount: \(wordCount)
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
