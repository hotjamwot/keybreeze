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
    """

    /// Build a continuation prompt from the given context.
    /// - Parameters:
    ///   - context: Text before cursor.
    ///   - styleNudge: Optional style guidance.
    ///   - maxWords: Maximum words to predict.
    /// - Returns: The prompt string to send to the LLM.
    static func continuationPrompt(context: String, styleNudge: String = "", maxWords: Int = 8) -> String {
        var prompt = context
        if !styleNudge.isEmpty {
            prompt += "\n\nStyle: \(styleNudge)"
        }
        prompt += "\n\nContinue naturally (max \(maxWords) words):"
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