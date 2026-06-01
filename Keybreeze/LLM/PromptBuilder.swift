import Foundation

/// Builds prompts for the LLM with appropriate system instructions and context.
enum PromptBuilder {
    /// Default system prompt for text continuation.
    static let defaultSystemPrompt = """
    You are a text continuation engine. Your job is to predict the next few words the user is likely to type.
    Rules:
    - Only output the continuation text. No explanations, no markdown.
    - Keep continuations short (1-8 words).
    - Prefer common, predictable phrasing.
    - Match the user's writing style and tone.
    - If the text ends mid-sentence, complete it naturally.
    - If the text could end many ways, pick the most likely completion.
    - NEVER restate or repeat the last word or phrase from the input.
    - NEVER use ellipsis (...), dashes (—), or any stylistic prefixes.
    - Always start with a fresh word that continues the sentence.
    - NEVER start with ellipsis (...), dashes (—), or any punctuation prefix.
    - If the user's text ends mid-word, complete that word naturally from where it left off.
    """

    /// Build a continuation prompt from the given context.
    /// - Parameters:
    ///   - context: Text before cursor.
    ///   - textAfterCursor: Text that already exists after the cursor position.
    ///     When provided, the prompt includes this context so the model avoids
    ///     duplicating text that the user has already typed or that follows the
    ///     cursor. This is the single most impactful change for reducing
    ///     multi-line and duplicated suggestions (Known Issue #2).
    ///   - styleNudge: Optional style guidance.
    ///   - maxWords: Maximum words to predict.
    ///   - raw: When true, formats as raw text for the llama.cpp `/completion`
    ///     endpoint with `--no-jinja`. No chat template tokens or instructions
    ///     are added — just the bare context. The model will complete it naturally
    ///     as a text continuation (not a chatbot response).
    ///   - systemPromptOverride: Ignored in raw mode (no system prompt is sent).
    /// - Returns: The prompt string to send to the LLM.
    static func continuationPrompt(
        context: String,
        textAfterCursor: String = "",
        styleNudge: String = "",
        maxWords: Int = 8,
        raw: Bool = false,
        systemPromptOverride: String? = nil
    ) -> String {
        let afterTrimmed = textAfterCursor.trimmingCharacters(in: .whitespacesAndNewlines)

        if raw {
            // Raw completion endpoint with --no-jinja: send the context as-is,
            // with a trailing space appended if the context doesn't end with one.
            //
            // When after-cursor text is available, append it with a bracket
            // marker. The model sees the full picture: what came before the
            // cursor, followed by what already exists after it. This lets it
            // predict bridge text that connects the two, rather than duplicating
            // the after-cursor content.
            //
            // Example: "The quick brown " → "The quick brown [AFTER: fox jumps]"
            // The model then predicts "fox jumps" naturally as bridge text,
            // instead of hallucinating "fox jumps over the lazy dog" which would
            // duplicate the existing "fox jumps".
            var prompt = context
            if !afterTrimmed.isEmpty {
                prompt += "[AFTER:\(afterTrimmed)]"
            }
            if !prompt.hasSuffix(" ") {
                prompt += " "
            }
            return prompt
        }
        var prompt = context
        if !afterTrimmed.isEmpty {
            prompt += "\n\nText after cursor: \(afterTrimmed)"
            prompt += "\nDo not repeat or include the text after the cursor."
        }
        if !styleNudge.isEmpty {
            prompt += "\n\nStyle: \(styleNudge)"
        }
        prompt += "\n\nContinue with the next few words only:\n"
        return prompt
    }

    /// Build a system prompt with optional overrides.
    static func systemPrompt(customPrompt: String = "", styleNudge: String = "") -> String {
        if !customPrompt.isEmpty { return customPrompt }
        if !styleNudge.isEmpty {
            return defaultSystemPrompt + "\n\nWriting style: \(styleNudge)"
        }
        return defaultSystemPrompt
    }
}