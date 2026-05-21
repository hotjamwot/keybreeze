import Foundation

/// Model option - simplified version.
struct ModelOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let ollamaId: String
    let ggufPath: String?
    let maxWords: Int

    // Runtime parameters
    let temperature: Double
    let topP: Double
    let repeatPenalty: Double
    let confidenceThreshold: Double

    var isGGUF: Bool { ggufPath != nil }

    static let defaultTemperature: Double = 0.35
    static let defaultTopP: Double = 0.85
    static let defaultRepeatPenalty: Double = 1.02
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