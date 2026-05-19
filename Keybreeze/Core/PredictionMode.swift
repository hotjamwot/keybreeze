import Foundation

/// Scheduler timing mode: fast mid-type vs longer pause prediction.
enum PredictionMode: String, Sendable {
    case midType
    case pause

    var debounceMilliseconds: Int {
        switch self {
        case .midType: 400
        case .pause: 800
        }
    }

    /// Word cap for this mode, clamped to the model's configured maximum.
    func maxWords(modelCap: Int) -> Int {
        let cap = max(modelCap, PromptBuilder.minCompletionWords)
        switch self {
        case .midType:
            return min(6, max(PromptBuilder.minCompletionWords, cap / 2))
        case .pause:
            return cap
        }
    }
}
