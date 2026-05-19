import Foundation

/// Global LLM configuration that encapsulates all backend-specific settings.
struct LLMConfiguration {
    var ollamaConfiguration: OllamaConfiguration
    var llamaCppConfiguration: LlamaCppConfiguration
    
    init(
        ollamaConfiguration: OllamaConfiguration = OllamaConfiguration(),
        llamaCppConfiguration: LlamaCppConfiguration = LlamaCppConfiguration()
    ) {
        self.ollamaConfiguration = ollamaConfiguration
        self.llamaCppConfiguration = llamaCppConfiguration
    }
}