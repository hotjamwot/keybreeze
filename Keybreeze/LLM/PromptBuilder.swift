import Foundation

/// Builds a tight continuation prompt from editor context. Keeps provider-specific formatting out of the network layer.
enum PromptBuilder {
    /// Minimum **words** we ask the model to emit (fixed product rule).
    static let minCompletionWords = 1

    /// Returns true if the text ends mid-word (no trailing whitespace, last char not punctuation).
    private static func isMidWord(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters)
        return !terminators.contains(last)
    }

    /// Returns true if the text ends mid-sentence but could be complete (ends with sentence-ending punctuation).
    private static func isSentenceComplete(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return last == "." || last == "!" || last == "?" || last == "\n"
    }

    /// The default system prompt built into the engine.
    /// Optimized for tight inline text completions that flow naturally from the context.
    static let defaultSystemPrompt: String = """
        You are a native macOS inline text completion engine. Your job is to predict what the user is about to type next.

        Rules:
        - Output ONLY the continuation text — no labels, quotes, formatting, or punctuation at the start.
        - Never output leading spaces or punctuation. Start directly with the continuation word(s).
        - Match the user's tone, formatting, casing, and style exactly.
        - Think about what word or phrase flows most naturally from the context. Prefer completions that form a coherent sentence.
        - When the user is mid-sentence, predict the most natural complete phrase (2-8 words).
        - When the text looks complete with no obvious continuation, output nothing.
        - STOP immediately after the continuation — do not add explanations or extra text.
        """

    /// Creates a short completion prompt following the Quinn 2.53b coder paradigm.
    /// - Parameters:
    ///   - customSystemPrompt: If non-empty, replaces the built-in system-level framing.
    ///   - styleNudge: If non-empty, appended as extra style guidance (gentle nudges only).
    ///   - midTypeWords: Per-mode cap for mid-type predictions.
    ///   - pauseWords: Per-mode cap for pause predictions.
    ///   - mode: The current prediction mode (midType vs pause), used to determine word cap.
    static func continuationPrompt(
        for state: EditorState,
        modelOption: ModelOption,
        customSystemPrompt: String = "",
        styleNudge: String = "",
        midTypeWords: Int = 0,
        pauseWords: Int = 0,
        mode: PredictionMode = .midType
    ) -> String {
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
        let sentenceComplete = !midWord && isSentenceComplete(trimmedBefore)

        // Calculate word cap based on mode
        let cappedMax: Int
        if mode == .midType {
            let preferred = midTypeWords > 0 ? midTypeWords : PredictionMode.defaultMidTypeWords
            cappedMax = max(minCompletionWords, min(preferred, modelOption.maxWords))
        } else {
            let preferred = pauseWords > 0 ? pauseWords : PredictionMode.defaultPauseWords
            cappedMax = max(minCompletionWords, min(preferred, modelOption.maxWords))
        }

        // Build contextually-aware continuation instruction
        let continuationRule: String
        if midWord {
            // User is mid-word — complete this word, then optionally continue naturally
            continuationRule = """
            The user is MID-WORD (no trailing space). Complete the current word, then optionally \
            add the most natural continuation — think about what word/phrase flows from this context. \
            Output up to \(cappedMax) total words.
            """
        } else if sentenceComplete {
            // Sentence just ended — only predict if continuation is very obvious
            continuationRule = """
            The text ends with a COMPLETE SENTENCE (punctuation at end of context). \
            Only predict if there is an extremely obvious continuation (e.g. the user is listing items, \
            or the sentence structure clearly requires a follow-up). Otherwise output nothing.
            """
        } else {
            // Mid-sentence with trailing space — predict a natural multi-word phrase
            continuationRule = """
            The user is MID-SENTENCE (ends with a space after typing a word). \
            Predict the most natural continuation — this is usually a few words that complete \
            the thought. Think about what a native speaker would naturally type next. \
            Output up to \(cappedMax) natural-sounding words.
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
        \(continuationRule)

        \(nudgeSection)\(style)

        Text before caret:
        \(trimmedBefore)

        Text after caret (may be empty):
        \(trimmedAfter)

        Continue immediately from the end of "Text before caret" without repeating it.
        Output the continuation only — maximum \(cappedMax) word(s), then STOP.
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