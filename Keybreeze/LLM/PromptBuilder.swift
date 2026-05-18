import Foundation

/// Builds a tight continuation prompt from editor context. Keeps provider-specific formatting out of the network layer.
enum PromptBuilder {
    /// Minimum **words** we ask the model to emit (fixed product rule).
    static let minCompletionWords = 2

    /// Produces a short completion prompt: natural continuation only, no meta commentary.
    static func continuationPrompt(for state: EditorState, modelOption: ModelOption) -> String {
        let cappedMax = max(modelOption.maxWords, minCompletionWords)
        let trimmedBefore = state.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAfter = state.textAfterCursor.trimmingCharacters(in: .whitespacesAndNewlines)

        let style = styleProfileSection(for: modelOption)

        return """
        You are a typing continuation engine, not a chat assistant.

        Rules (non-negotiable):
        - ONLY continue the text from the end of “Text before caret”.
        - DO NOT explain.
        - DO NOT describe reasoning.
        - DO NOT summarize.
        - DO NOT answer questions.
        - DO NOT prefix with labels (“Sure:”, “Here:”, etc.).
        - DO NOT quote, bullet, or repeat text already written.
        - OUTPUT ONLY the continuation text (plain text, no markdown).
        - Maximum \(minCompletionWords)–\(cappedMax) words total, then STOP.
        - Match tone, register, and punctuation of the existing fragment exactly.

        \(style)

        Text before caret:
        \(trimmedBefore)

        Text after caret (may be empty):
        \(trimmedAfter)

        Continue immediately from the end of “Text before caret” without repeating it.
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
