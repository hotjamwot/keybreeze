import Foundation

/// Builds a tight continuation prompt from editor context. Keeps provider-specific formatting out of the network layer.
enum PromptBuilder {
    /// Minimum **words** we ask the model to emit (fixed product rule).
    static let minCompletionWords = 2

    /// Returns true if the text ends mid-word (no trailing whitespace, last char not punctuation).
    private static func isMidWord(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters)
        return !terminators.contains(last)
    }

    /// The default system prompt built into the engine.
    /// Optimized for tight predictive completions (1-5 words max).
    static let defaultSystemPrompt: String = """
        You are a native macOS inline text completion engine. Your sole job is to seamlessly continue the text provided by the user.
        - Do NOT talk to the user. Do NOT write explanations or greetings.
        - Match the user's tone, formatting, casing, and style exactly.
        - Complete the thought starting from the exact last character provided.
        - Keep your generation short (1 to 5 words maximum).
        - Do NOT repeat any words or phrases from the context.
        - If the text looks complete or no obvious continuation exists, return nothing.
        """

    /// Creates a short completion prompt following the Quinn 2.53b coder paradigm.
    /// - Parameters:
    ///   - customSystemPrompt: If non-empty, replaces the built-in system-level framing.
    ///   - styleNudge: If non-empty, appended as extra style guidance (for gentle nudges only).
    static func continuationPrompt(
        for state: EditorState,
        modelOption: ModelOption,
        customSystemPrompt: String = "",
        styleNudge: String = ""
    ) -> String {
        let cappedMax = max(modelOption.maxWords, minCompletionWords)
        let trimmedBefore = state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAfter = state.textAfterCursor.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use custom system prompt if provided, else fall back to default
        let systemPrompt: String
        if !customSystemPrompt.isEmpty {
            systemPrompt = customSystemPrompt
        } else {
            systemPrompt = defaultSystemPrompt
        }

        let style = styleProfileSection(for: modelOption)

        let midWord = isMidWord(trimmedBefore)
        let wordContinuationRule: String
        if midWord {
            wordContinuationRule = """
            - The user is MID-WORD (no space at end). FIRST complete the current word, then continue with more.
            """
        } else {
            wordContinuationRule = """
            - The user finished a word (ends with space). Continue with the next natural words.
            """
        }

        // Style nudge — optional gentle addition appended before the style profile
        let nudgeSection: String
        if !styleNudge.isEmpty {
            nudgeSection = """
            Style nudge:
            \(styleNudge)

            """
        } else {
            nudgeSection = ""
        }

        return """
        \(systemPrompt)

        Additional instructions:
        \(wordContinuationRule)

        \(nudgeSection)\(style)

        Text before caret:
        \(trimmedBefore)

        Text after caret (may be empty):
        \(trimmedAfter)

        Continue immediately from the end of "Text before caret" without repeating it.
        Maximum \(minCompletionWords)–\(cappedMax) words total, then STOP.
        """
    }

    private static func styleProfileSection(for model: ModelOption) -> String {
        """
        Style profile:
        - verbosity: \(verbosityLabel(model.verbosityBias))
        - continuation: \(continuationLabel(model.continuationBias))
        - instruction adherence: \(instructionAdherenceLabel(model.instructionStrictness))
        """
    }

    private static func verbosityLabel(_ bias: Double) -> String {
        if bias < 0.34 { "low" }
        else if bias < 0.67 { "medium" }
        else { "high" }
    }

    private static func continuationLabel(_ bias: Double) -> String {
        if bias >= 0.55 { "strict" }
        else if bias >= 0.35 { "balanced" }
        else { "loose" }
    }

    private static func instructionAdherenceLabel(_ strictness: Double) -> String {
        if strictness >= 0.85 { "high" }
        else if strictness >= 0.65 { "medium" }
        else { "low" }
    }
}
