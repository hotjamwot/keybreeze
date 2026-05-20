import Foundation
import AppKit

/// Manages backspace correction detection and state.
class CorrectionManager {
    /// Tracks the number of consecutive backspaces detected.
    private var backspaceCount: Int = 0
    /// Tracks the text state before backspaces occurred, used to detect deletion patterns.
    private var textBeforeBackspace: String = ""
    /// Current correction state (if any).
    private var correctionState: CorrectionState?

    /// Detects and handles correction suggestion when user backspaces through a word.
    /// Returns the new correction state (if any).
    func detectCorrection(draftText: String, previousDraftText: String) -> CorrectionState? {
        // Detect backspace events by comparing with previous text
        let currentLength = draftText.count
        let previousLength = previousDraftText.count
        
        // Check if text was deleted from the end (backspace)
        if currentLength < previousLength && 
           draftText == String(previousDraftText.prefix(currentLength)) {
            // Deletion occurred at the end - likely backspaces
            backspaceCount += 1
        } else {
            // Text was modified in a non-backspace way, reset counter
            backspaceCount = 0
        }
        
        // If backspace threshold reached, trigger correction detection
        if backspaceCount >= 3, correctionState == nil, !draftText.isEmpty {
            return detectCorrection(draftText: draftText, previousDraftText: previousDraftText)
        }
        
        return nil
    }

    private func detectCorrectionInternal(draftText: String, previousDraftText: String) -> CorrectionState? {
        // Find the word that was being typed before backspaces
        // We look at textBeforeBackspace and find the last word that was partially deleted
        let fullTextBeforeBackspace = previousDraftText
        let currentLength = draftText.count
        
        // The deleted portion is the suffix of fullTextBeforeBackspace
        let deletedSuffix = fullTextBeforeBackspace.dropFirst(currentLength)
        
        // If the deleted text is just whitespace or empty, no correction needed
        let trimmedDeleted = deletedSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDeleted.isEmpty else {
            return nil
        }
        
        // Find the start of the last word in the remaining text that aligns with the deleted suffix
        // We need to find where the last word begins in fullTextBeforeBackspace
        let remainingText = String(fullTextBeforeBackspace.prefix(currentLength))
        
        // Get the last word from the remaining text (if any)
        let words = remainingText.split(separator: " ", omittingEmptySubsequences: false)
        guard let lastWord = words.last, !lastWord.isEmpty else {
            return nil
        }
        
        // The incorrect word is the lastWord plus the deleted suffix (they should form a continuous word)
        // Actually, the incorrect word is the full word that was partially deleted.
        // We need to reconstruct the full word from what remains and what was deleted.
        let fullIncorrectWord = lastWord + deletedSuffix
        
        // For now, this is a placeholder. In a real implementation, we would:
        // 1. Run a quick prediction with the context up to this word to get the correction
        // 2. Or use a spelling dictionary to suggest corrections
        
        // For demonstration, we'll just use the fullIncorrectWord as both incorrect and suggested (no change)
        // In production, we'd get a proper suggestion from the model.
        let range = NSRange(location: remainingText.count - lastWord.count, length: fullIncorrectWord.count)
        
        return CorrectionState(
            incorrectWord: String(fullIncorrectWord),
            suggestedCorrection: String(fullIncorrectWord), // Placeholder - should be actual correction
            range: range,
            timestamp: Date()
        )
    }

    /// Accept the current correction: replace the incorrect word with the suggested correction.
    /// Returns the corrected word, or empty if no correction.
    func acceptCorrection(draftText: String, correction: CorrectionState) -> String {
        // Replace the incorrect word with the suggested correction
        let range = correction.range
        let correctedText = String(draftText.prefix(range.location)) + correction.suggestedCorrection + String(draftText.dropFirst(range.location + range.length))
        return correctedText
    }

    /// Reject the current correction: dismiss the correction UI without changes.
    func rejectCorrection() {
        // Clear correction state
        correctionState = nil
    }
}
