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
        styleNudge: String = "",
        maxWords: Int = 8,
        raw: Bool = false,
        systemPromptOverride: String? = nil
    ) -> String {
        if raw {
            // Raw completion endpoint with --no-jinja: send the context as-is,
            // with a trailing space appended if the context doesn't end with one.
            //
            // The trailing space converts mid-word contexts ("best b") into clean
            // word-boundary contexts ("best b "). This prevents the model from
            // struggling with partial-word inputs at low temperature — instead
            // of trying to complete "b" character-by-character, it predicts the
            // most likely word following "b", which matches the user's intent.
            //
            // By contrast, the old chat template approach
            // (<start_of_turn>system/user/model) forced the instruct model into
            // chatbot mode, producing empty responses for mid-word inputs,
            // safety refusals for full sentences, and system prompt leakage.
            //
            // Bare text with repeat_penalty at low temperature produces clean
            // natural language continuations, not HTML/code.
            if context.hasSuffix(" ") {
                return context
            }
            return context + " "
        }
        var prompt = context
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