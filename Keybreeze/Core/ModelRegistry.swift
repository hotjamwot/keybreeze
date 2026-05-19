import Foundation

/// A user-visible model choice mapped to a provider-specific model id (Ollama tag or GGUF path).
struct ModelOption: Equatable, Hashable, Identifiable, Sendable {
    /// Stable app id (menus, persistence); for catalog-driven models this matches `ollamaId`.
    let id: String
    let displayName: String
    /// Ollama model tag passed to `/api/generate` (e.g. `gemma2:2b`). Empty for GGUF models.
    let ollamaId: String
    /// Absolute path to a GGUF file, if this is a llama.cpp model. Nil for Ollama models.
    let ggufPath: String?
    /// Upper bound for streamed completion length (UI / post-process; prompt uses the same cap).
    let maxWords: Int

    /// Higher → model tends to be more verbose; we steer prompts toward lower effective verbosity when this is low.
    let verbosityBias: Double
    /// Higher → stricter "continue the fragment" behaviour in the style profile.
    let continuationBias: Double
    /// Higher → stronger instruction-following framing in the prompt.
    let instructionStrictness: Double

    // MARK: — Runtime model parameters (Typing Lab)

    /// LLM temperature. Higher = more creative, lower = more deterministic.
    let temperature: Double
    /// Top-p sampling parameter.
    let topP: Double
    /// Repeat penalty to discourage repetition.
    let repeatPenalty: Double
    /// Presence penalty to reduce repeated word usage (Ollama only).
    let presencePenalty: Double
    /// Confidence threshold: predictions below this are not displayed.
    let confidenceThreshold: Double

    /// Whether this model is a local GGUF file (for llama.cpp).
    var isGGUF: Bool { ggufPath != nil }
}

extension ModelOption {
    /// Default runtime parameter values used when not overridden.
    static let defaultTemperature: Double = 0.35
    static let defaultTopP: Double = 0.85
    static let defaultRepeatPenalty: Double = 1.02
    static let defaultPresencePenalty: Double = 0.1
    static let defaultConfidenceThreshold: Double = 0.25
}

/// Tuning presets keyed by exact Ollama tag. Tags from `GET /api/tags` are merged here; unknown tags get defaults.
enum ModelRegistry {
    static let qwen25_coder_3b = ModelOption(
        id: "qwen25-coder-3b",
        displayName: "Qwen 2.5 Coder 3B",
        ollamaId: "qwen2.5-coder:3b",
        ggufPath: nil,
        maxWords: 12,
        verbosityBias: 0.2,
        continuationBias: 0.6,
        instructionStrictness: 0.95,
        temperature: 0.35,
        topP: 0.85,
        repeatPenalty: 1.02,
        presencePenalty: 0.1,
        confidenceThreshold: 0.25
    )

    static let qwen25_3B = ModelOption(
        id: "qwen25-3b",
        displayName: "Qwen 2.5 3B",
        ollamaId: "qwen2.5:3b",
        ggufPath: nil,
        maxWords: 12,
        verbosityBias: 0.3,
        continuationBias: 0.5,
        instructionStrictness: 0.95,
        temperature: ModelOption.defaultTemperature,
        topP: ModelOption.defaultTopP,
        repeatPenalty: ModelOption.defaultRepeatPenalty,
        presencePenalty: ModelOption.defaultPresencePenalty,
        confidenceThreshold: ModelOption.defaultConfidenceThreshold
    )

    static let gemma2_2B = ModelOption(
        id: "gemma2-2b",
        displayName: "Gemma 2 2B",
        ollamaId: "gemma2:2b",
        ggufPath: nil,
        maxWords: 12,
        verbosityBias: 0.35,
        continuationBias: 0.4,
        instructionStrictness: 0.9,
        temperature: ModelOption.defaultTemperature,
        topP: ModelOption.defaultTopP,
        repeatPenalty: ModelOption.defaultRepeatPenalty,
        presencePenalty: ModelOption.defaultPresencePenalty,
        confidenceThreshold: ModelOption.defaultConfidenceThreshold
    )

    static let gemma4_e2b_q4 = ModelOption(
        id: "batiai_gemma4_e2b_q4",
        displayName: "Gemma 4 2B Q4",
        ollamaId: "batiai/gemma4-e2b:q4",
        ggufPath: nil,
        maxWords: 12,
        verbosityBias: 0.1,
        continuationBias: 0.4,
        instructionStrictness: 0.9,
        temperature: 0.3,
        topP: 0.8,
        repeatPenalty: ModelOption.defaultRepeatPenalty,
        presencePenalty: ModelOption.defaultPresencePenalty,
        confidenceThreshold: ModelOption.defaultConfidenceThreshold
    )

    private static let presetsByOllamaId: [String: ModelOption] = [
        qwen25_coder_3b.ollamaId: qwen25_coder_3b,
        qwen25_3B.ollamaId: qwen25_3B,
        gemma2_2B.ollamaId: gemma2_2B,
        gemma4_e2b_q4.ollamaId: gemma4_e2b_q4,
    ]

    /// Default selection before the first successful catalog refresh (or when Ollama is unreachable).
    static var defaultModel: ModelOption { qwen25_coder_3b }

    /// Resolves an Ollama tag to a `ModelOption`, applying known presets when the tag matches.
    static func option(resolvingOllamaTag tag: String) -> ModelOption {
        if let known = presetsByOllamaId[tag] {
            return known
        }
        return ModelOption(
            id: tag,
            displayName: tag,
            ollamaId: tag,
            ggufPath: nil,
            maxWords: 12,
            verbosityBias: 0.35,
            continuationBias: 0.45,
            instructionStrictness: 0.88,
            temperature: ModelOption.defaultTemperature,
            topP: ModelOption.defaultTopP,
            repeatPenalty: ModelOption.defaultRepeatPenalty,
            presencePenalty: ModelOption.defaultPresencePenalty,
            confidenceThreshold: ModelOption.defaultConfidenceThreshold
        )
    }
}