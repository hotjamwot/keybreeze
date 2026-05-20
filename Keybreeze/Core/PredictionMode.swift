import Foundation

/// Scheduler timing mode: fast mid-type vs longer pause prediction.
enum PredictionMode: String, Sendable {
    case midType
    case pause

    /// Default maximum words for mid-type predictions (fast, aggressive).
    static let defaultMidTypeWords: Int = 4
    /// Default maximum words for pause predictions (slightly more context).
    static let defaultPauseWords: Int = 8
    /// Minimum words to ever produce.
    static let minWords: Int = 1
    /// Maximum configurable words.
    static let maxWordsLimit: Int = 15

    var debounceMilliseconds: Int {
        switch self {
        case .midType: 400
        case .pause: 800
        }
    }

    /// Word cap for this mode using configurable per-mode limits.
    /// - Parameters:
    ///   - midTypeWords: Override for mid-type word cap (0 = use default).
    ///   - pauseWords: Override for pause word cap (0 = use default).
    ///   - modelCap: Model's configured maximum word limit.
    func maxWords(midTypeWords: Int = 0, pauseWords: Int = 0, modelCap: Int) -> Int {
        let cap = max(modelCap, Self.minWords)
        switch self {
        case .midType:
            let preferred = midTypeWords > 0 ? midTypeWords : Self.defaultMidTypeWords
            return max(Self.minWords, min(preferred, cap))
        case .pause:
            let preferred = pauseWords > 0 ? pauseWords : Self.defaultPauseWords
            return max(Self.minWords, min(preferred, cap))
        }
    }
}