import Foundation

/// Builds prompts for the LLM with sectioned, budgeted context inspired by
/// KeyType's PromptBuilder. Sections are allocated token budget by priority
/// and rendered in a fixed order so the model's next token is the natural
/// continuation of the user's text at the caret.
///
/// Key design principles (from KeyType ADR-017):
/// - `beforeCursor` is always last in the prompt (base mode) so the model
///   completes naturally at the caret position.
/// - Trailing whitespace at the caret is trimmed to prevent double-space
///   artifacts on insertion.
/// - Each section has a priority and token budget; lower-priority sections
///   are truncated first when the total exceeds the budget.
/// - Per-app environment context gating prevents code-editor metadata from
///   biasing prose predictions.
enum PromptBuilder {

    // MARK: - Token Budget

    /// Approximate token count: ~4 characters per token (GPT-style BPE).
    /// Good enough for budget allocation without a real tokenizer.
    static func approximateTokenCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    /// Maximum prompt tokens (sized for steady-state with Ollama).
    static let defaultMaxPromptTokens = 2048

    // MARK: - Prompt Sections

    struct PromptSection {
        let name: String
        let heading: String?
        var content: String
        let priority: Int        // Higher = more important, kept first
        let minBudget: Int       // Minimum tokens to include
        let maxBudget: Int       // Maximum tokens allowed
    }

    // MARK: - Public API

    /// Build a continuation prompt from the given context.
    /// - Parameters:
    ///   - context: Text before cursor.
    ///   - textAfterCursor: Text that already exists after the cursor position.
    ///     When provided, the prompt includes this context so the model avoids
    ///     duplicating text that the user has already typed or that follows the
    ///     cursor.
    ///   - styleNudge: Optional style guidance.
    ///   - maxWords: Maximum words to predict.
    ///   - raw: When true, formats as raw text for the llama.cpp `/completion`
    ///     endpoint with `--no-jinja`. No chat template tokens or instructions
    ///     are added — just the bare context. The model will complete it naturally
    ///     as a text continuation (not a chatbot response).
    ///   - systemPromptOverride: Ignored in raw mode (no system prompt is sent).
    ///   - appName: Current app name for environment context (omitted for code editors).
    ///   - bundleIdentifier: Bundle ID for per-app prompt gating.
    ///   - customInstructions: App-specific prompt instructions.
    /// - Returns: The prompt string to send to the LLM.
    static func continuationPrompt(
        context: String,
        textAfterCursor: String = "",
        styleNudge: String = "",
        maxWords: Int = 8,
        raw: Bool = false,
        systemPromptOverride: String? = nil,
        appName: String = "",
        bundleIdentifier: String = "",
        customInstructions: String = ""
    ) -> String {
        if raw {
            return buildRawPrompt(
                context: context,
                textAfterCursor: textAfterCursor
            )
        }
        return buildSectionedPrompt(
            context: context,
            textAfterCursor: textAfterCursor,
            styleNudge: styleNudge,
            maxWords: maxWords,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            customInstructions: customInstructions
        )
    }

    /// Build a system prompt with optional overrides.
    static func systemPrompt(customPrompt: String = "", styleNudge: String = "") -> String {
        if !customPrompt.isEmpty { return customPrompt }
        if !styleNudge.isEmpty {
            return defaultSystemPrompt + "\n\nWriting style: \(styleNudge)"
        }
        return defaultSystemPrompt
    }

    // MARK: - Raw Prompt (llama.cpp)

    /// Raw completion endpoint with --no-jinja: send the context as-is,
    /// with a trailing space appended if the context doesn't end with one.
    ///
    /// When after-cursor text is available, append it with a bracket
    /// marker. The model sees the full picture: what came before the
    /// cursor, followed by what already exists after it. This lets it
    /// predict bridge text that connects the two, rather than duplicating
    /// the after-cursor content.
    private static func buildRawPrompt(
        context: String,
        textAfterCursor: String
    ) -> String {
        let afterTrimmed = textAfterCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = trimmingTrailingWhitespace(context)
        if !afterTrimmed.isEmpty {
            prompt += "[AFTER:\(afterTrimmed)]"
        }
        if !prompt.hasSuffix(" ") {
            prompt += " "
        }
        return prompt
    }

    // MARK: - Sectioned Prompt (Ollama / ChatML)

    /// Builds a prompt with named sections, each allocated token budget by priority.
    /// Sections are rendered in a fixed order; `beforeCursor` is always last so the
    /// model's next token is the natural continuation at the caret.
    private static func buildSectionedPrompt(
        context: String,
        textAfterCursor: String,
        styleNudge: String,
        maxWords: Int,
        appName: String,
        bundleIdentifier: String,
        customInstructions: String
    ) -> String {
        let sections = makeSections(
            context: context,
            textAfterCursor: textAfterCursor,
            styleNudge: styleNudge,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            customInstructions: customInstructions
        )

        let contentBudget = defaultMaxPromptTokens
        let allocated = allocate(sections: sections, contentBudget: contentBudget)
        let body = renderBody(allocated)

        return body
    }

    // MARK: - Section Construction

    private static func makeSections(
        context: String,
        textAfterCursor: String,
        styleNudge: String,
        appName: String,
        bundleIdentifier: String,
        customInstructions: String
    ) -> [PromptSection] {
        var sections: [PromptSection] = [
            // Highest priority: the instruction that frames the task
            PromptSection(
                name: "completionInstructions",
                heading: "Completion instructions",
                content: "Continue the user's current text at the cursor. Produce only text that should be inserted. Keep continuations short (1-\(maxWords) words). Match the user's writing style and tone.",
                priority: 100,
                minBudget: 16,
                maxBudget: 96
            )
        ]

        // App/environment context — omitted for code editors and terminals
        // where it biases the model toward code/numbers rather than prose.
        let includeEnvironment = !AppCompatibility.isEnvironmentContextDisabled(for: bundleIdentifier)
        if includeEnvironment && !appName.isEmpty {
            sections.append(
                PromptSection(
                    name: "generalInfo",
                    heading: "General information",
                    content: "Application: \(appName)",
                    priority: 60,
                    minBudget: 0,
                    maxBudget: 96
                )
            )
        }

        // After-cursor context — prevents the model from duplicating existing text
        let afterTrimmed = textAfterCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !afterTrimmed.isEmpty {
            sections.append(
                PromptSection(
                    name: "afterCursor",
                    heading: "Text after cursor",
                    content: afterTrimmed,
                    priority: 90,
                    minBudget: 0,
                    maxBudget: 256
                )
            )
        }

        // Style nudge
        if !styleNudge.isEmpty {
            sections.append(
                PromptSection(
                    name: "styleNudge",
                    heading: "Writing style",
                    content: styleNudge,
                    priority: 70,
                    minBudget: 0,
                    maxBudget: 64
                )
            )
        }

        // Custom per-app instructions
        if !customInstructions.isEmpty {
            sections.append(
                PromptSection(
                    name: "customInstructions",
                    heading: "App-specific instructions",
                    content: customInstructions,
                    priority: 80,
                    minBudget: 0,
                    maxBudget: 128
                )
            )
        }

        // Before cursor — the main context. Trailing whitespace trimmed to
        // prevent double-space artifacts on insertion (KeyType ADR-017).
        sections.append(
            PromptSection(
                name: "beforeCursor",
                heading: "Text before cursor",
                content: trimmingTrailingWhitespace(context),
                priority: 100,
                minBudget: 64,
                maxBudget: 1024
            )
        )

        return sections
    }

    // MARK: - Budget Allocation

    /// Allocates token budget across sections in priority order.
    /// Higher-priority sections get their full allocation first;
    /// lower-priority sections are truncated to fit the remaining budget.
    private static func allocate(sections: [PromptSection], contentBudget: Int) -> [PromptSection] {
        let separatorTokens = 2 // "\n\n" ≈ 2 tokens
        let priorityOrdered = sections.sorted {
            $0.priority == $1.priority ? $0.name < $1.name : $0.priority > $1.priority
        }

        var remaining = contentBudget
        var allocated: [PromptSection] = []
        allocated.reserveCapacity(priorityOrdered.count)

        for (index, section) in priorityOrdered.enumerated() {
            let headingOverhead = section.heading.map { approximateTokenCount(for: "[\($0)]\n") } ?? 0
            let separatorOverhead = index == 0 ? 0 : separatorTokens
            let fixedOverhead = headingOverhead + separatorOverhead

            let preferred = approximateTokenCount(for: section.content)
            let target = min(section.maxBudget, max(section.minBudget, preferred))
            let cap = max(0, remaining - fixedOverhead)
            let budget = min(target, cap)

            var copy = section
            copy.content = truncateToTokens(section.content, targetTokens: budget)
            let actualTokens = approximateTokenCount(for: copy.content)
            remaining = max(0, remaining - actualTokens - fixedOverhead)
            allocated.append(copy)
        }

        return allocated.sorted { sectionOrder($0.name) < sectionOrder($1.name) }
    }

    // MARK: - Truncation

    /// Truncates text to fit within a token budget by binary searching on
    /// character boundaries. Keeps the tail (nearest to caret) for beforeCursor
    /// and the head for other sections.
    private static func truncateToTokens(_ text: String, targetTokens: Int) -> String {
        if targetTokens <= 0 { return "" }
        if text.isEmpty { return text }
        if approximateTokenCount(for: text) <= targetTokens { return text }

        // Binary search for the largest prefix/suffix that fits
        let count = text.count
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let slice = String(text.prefix(mid))
            if approximateTokenCount(for: slice) <= targetTokens {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return String(text.prefix(lo))
    }

    // MARK: - Rendering

    private static func renderBody(_ sections: [PromptSection]) -> String {
        sections.compactMap { section -> String? in
            guard !section.content.isEmpty else { return nil }
            if let heading = section.heading {
                return "[\(heading)]\n\(section.content)"
            }
            return section.content
        }.joined(separator: "\n\n")
    }

    /// Section ordering in the final prompt. `beforeCursor` is always last
    /// so the model's next token is the natural continuation at the caret.
    private static func sectionOrder(_ name: String) -> Int {
        [
            "completionInstructions",
            "customInstructions",
            "generalInfo",
            "styleNudge",
            "afterCursor",
            "beforeCursor"
        ].firstIndex(of: name) ?? Int.max
    }

    // MARK: - Utilities

    /// Drops trailing whitespace (spaces, tabs, newlines) so the base-model
    /// prompt ends exactly at a word boundary. Prevents the model from
    /// generating a word with no leading space, which causes double-space
    /// artifacts on insertion.
    static func trimmingTrailingWhitespace(_ text: String) -> String {
        var view = Substring(text)
        while let last = view.last, last.isWhitespace {
            view = view.dropLast()
        }
        return String(view)
    }

    // MARK: - Default System Prompt

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

    private static let maxWords = 8
}