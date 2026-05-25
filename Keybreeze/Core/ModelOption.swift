import Foundation

/// Model option - simplified version.
///
/// SINGLE SOURCE OF TRUTH for all inference parameter defaults.
/// All other components (CompletionController, SessionViewModel, AggressionPreset)
/// MUST reference these static defaults rather than hardcoding their own values.
struct ModelOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let ollamaId: String
    let ggufPath: String?
    let maxWords: Int

    // Runtime parameters (per-model overrides; use static defaults as fallback)
    let temperature: Double
    let topP: Double
    let repeatPenalty: Double
    let confidenceThreshold: Double

    var isGGUF: Bool { ggufPath != nil }

    // ── Single source of truth for inference defaults ──
    // These are the production-tuned defaults for Gemma 4 E2B with llama.cpp.
    // Change these to update all components that reference them.
    static let defaultTemperature: Double = 0.1
    static let defaultTopP: Double = 0.85
    static let defaultRepeatPenalty: Double = 1.15    // prevents word echoing (was 1.02)
    static let defaultConfidenceThreshold: Double = 0.25

    static let defaultModel = ModelOption(
        id: "gemma2-2b",
        displayName: "Gemma 2 2B",
        ollamaId: "gemma2:2b",
        ggufPath: nil,
        maxWords: 5,
        temperature: defaultTemperature,
        topP: defaultTopP,
        repeatPenalty: defaultRepeatPenalty,
        confidenceThreshold: defaultConfidenceThreshold
    )

    static func option(resolvingOllamaTag tag: String) -> ModelOption {
        // Known presets
        if tag == "qwen2.5-coder:3b" {
            return ModelOption(
                id: "qwen25-coder-3b",
                displayName: "Qwen 2.5 Coder 3B",
                ollamaId: tag,
                ggufPath: nil,
                maxWords: 5,
                temperature: 0.25,
                topP: 0.8,
                repeatPenalty: 1.05,
                confidenceThreshold: 0.35
            )
        }

        // Default for unknown models
        return ModelOption(
            id: tag,
            displayName: tag,
            ollamaId: tag,
            ggufPath: nil,
            maxWords: 5,
            temperature: defaultTemperature,
            topP: defaultTopP,
            repeatPenalty: defaultRepeatPenalty,
            confidenceThreshold: defaultConfidenceThreshold
        )
    }
}