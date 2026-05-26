import Foundation

/// Tracks Keybreeze's own synthetic key events so inserted suggestions do not recursively trigger
/// the input pipeline and cause bogus follow-up completions.
///
/// When Keybreeze injects accepted text back into the focused app, the global event tap would
/// otherwise observe those synthetic key events and treat them like fresh user typing.
@MainActor
final class InputSuppressionController {
    private var remainingKeyDownSuppressions = 0
    private var suppressionExpiry = Date.distantPast

    /// Arms a short-lived suppression window for the synthetic keydown events Keybreeze is about to post.
    func registerSyntheticInsertion(expectedKeyDownCount: Int) {
        remainingKeyDownSuppressions = max(expectedKeyDownCount, 0)
        suppressionExpiry = Date().addingTimeInterval(1.0)
    }

    /// Consumes one pending suppression token if the current event still falls inside the expiry window.
    func consumeIfNeeded() -> Bool {
        guard remainingKeyDownSuppressions > 0 else {
            return false
        }

        guard Date() <= suppressionExpiry else {
            remainingKeyDownSuppressions = 0
            return false
        }

        remainingKeyDownSuppressions -= 1
        return true
    }

    /// Resets all suppression state.
    func reset() {
        remainingKeyDownSuppressions = 0
        suppressionExpiry = .distantPast
    }
}