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
    ///   - raw: When true, returns the context with NO instruction boilerplate.
    ///     Use for raw `/completion` endpoints (llama.cpp) where the model
    ///     continues the text directly without a chat template.
    /// - Returns: The prompt string to send to the LLM.
    static func continuationPrompt(context: String, styleNudge: String = "", maxWords: Int = 8, raw: Bool = false) -> String {
        if raw {
            // Raw mode: return context with only a style suffix if provided.
            // No "Continue the next few words" — the model simply continues the text.
            if !styleNudge.isEmpty {
                return context + "\n\nStyle: \(styleNudge)"
            }
            return context
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