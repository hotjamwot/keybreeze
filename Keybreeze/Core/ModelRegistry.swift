import Foundation

/// A user-visible model choice mapped to a provider-specific model id (Ollama tag today).
struct ModelOption: Equatable, Hashable, Identifiable, Sendable {
    /// Stable app id (menus, persistence); for catalog-driven models this matches `ollamaId`.
    let id: String
    let displayName: String
    /// Ollama model tag passed to `/api/generate` (e.g. `gemma2:2b`).
    let ollamaId: String
    /// Upper bound for streamed completion length (UI / post-process; prompt uses the same cap).
    let maxWords: Int

    /// Higher → model tends to be more verbose; we steer prompts toward lower effective verbosity when this is low.
    let verbosityBias: Double
    /// Higher → stricter “continue the fragment” behaviour in the style profile.
    let continuationBias: Double
    /// Higher → stronger instruction-following framing in the prompt.
    let instructionStrictness: Double
}

/// Tuning presets keyed by exact Ollama tag. Tags from `GET /api/tags` are merged here; unknown tags get defaults.
enum ModelRegistry {
    static let qwen25_3B = ModelOption(
        id: "qwen25-3b",
        displayName: "Qwen 2.5 3B",
        ollamaId: "qwen2.5:3b",
        maxWords: 12,
        verbosityBias: 0.3,
        continuationBias: 0.5,
        instructionStrictness: 0.95
    )

    static let gemma2_2B = ModelOption(
        id: "gemma2-2b",
        displayName: "Gemma 2 2B",
        ollamaId: "gemma2:2b",
        maxWords: 12,
        verbosityBias: 0.35,
        continuationBias: 0.4,
        instructionStrictness: 0.9
    )

    private static let presetsByOllamaId: [String: ModelOption] = [
        qwen25_3B.ollamaId: qwen25_3B,
        gemma2_2B.ollamaId: gemma2_2B,
    ]

    /// Default selection before the first successful catalog refresh (or when Ollama is unreachable).
    static var defaultModel: ModelOption { gemma2_2B }

    /// Resolves an Ollama tag to a `ModelOption`, applying known presets when the tag matches.
    static func option(resolvingOllamaTag tag: String) -> ModelOption {
        if let known = presetsByOllamaId[tag] {
            return known
        }
        return ModelOption(
            id: tag,
            displayName: tag,
            ollamaId: tag,
            maxWords: 12,
            verbosityBias: 0.35,
            continuationBias: 0.45,
            instructionStrictness: 0.88
        )
    }
}
