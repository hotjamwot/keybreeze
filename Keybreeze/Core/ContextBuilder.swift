import Foundation

/// Trims raw editor text into a focused snapshot suitable for prompting.
enum ContextBuilder {
    static let defaultMaxCharacters = 800

    /// Returns an `EditorState` with bounded context before the caret and extracted sentence hints for logging.
    ///
    /// First attempts to read real context from the currently focused application via the Accessibility
    /// API (two-strategy AX reader). If that fails (e.g. AX permissions not granted, no focused element,
    /// or the `UseAXContextReader` feature flag is off), falls back to the raw `EditorState` provided.
    /// This makes the AX integration transparent to callers — no callers need to change on failure.
    static func focusedState(from state: EditorState, maxCharacters: Int = defaultMaxCharacters) -> EditorState {
        // Try AX reader first — if it succeeds, build the EditorState from real app context
        if let axContext = AccessibilityManager.shared.getTextContext(maxChars: maxCharacters) {
            return EditorState(
                textBeforeCursor: axContext.prefix,
                textAfterCursor: axContext.suffix
            )
        }

        // Fall back to the raw EditorState (from Typing Lab draftText or scheduler state)
        let trimmedBefore = state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAfter = state.textAfterCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedBefore = String(trimmedBefore.suffix(maxCharacters))

        return EditorState(
            textBeforeCursor: boundedBefore,
            textAfterCursor: trimmedAfter
        )
    }

    /// Last sentence fragment ending at the caret (may be partial).
    static func currentSentence(in textBeforeCursor: String) -> String {
        guard !textBeforeCursor.isEmpty else { return "" }
        let boundaries = CharacterSet(charactersIn: ".!?\n")
        let parts = textBeforeCursor.components(separatedBy: boundaries)
        return parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? textBeforeCursor
    }

    /// Sentence immediately before `currentSentence`, if any.
    static func previousSentence(in textBeforeCursor: String) -> String {
        guard !textBeforeCursor.isEmpty else { return "" }
        let boundaries = CharacterSet(charactersIn: ".!?\n")
        let parts = textBeforeCursor
            .components(separatedBy: boundaries)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return "" }
        return parts[parts.count - 2]
    }
}
