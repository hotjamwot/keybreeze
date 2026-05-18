import Foundation

/// Helpers to cap streamed completions to a maximum word count without breaking mid-token too aggressively.
enum WordLimiter {
    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    /// Returns text truncated to at most `maxWords` words (whitespace-separated).
    static func truncateToMaxWords(_ text: String, maxWords: Int) -> String {
        guard maxWords > 0 else { return "" }
        var count = 0
        var result = ""
        for word in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            if word.isEmpty { continue }
            if count >= maxWords { break }
            if !result.isEmpty { result.append(" ") }
            result.append(String(word))
            count += 1
        }
        return result
    }
}
