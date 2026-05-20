import Foundation

/// Represents the state of a backspace correction in progress.
struct CorrectionState: Equatable {
    /// The incorrectly typed word that is being corrected.
    let incorrectWord: String
    /// The suggested correction.
    let suggestedCorrection: String
    /// The range of the incorrect word in the full text.
    let range: NSRange
    /// Timestamp when the correction was detected.
    let timestamp: Date
}