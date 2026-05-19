import Foundation

/// Available inference backends. Allows side-by-side comparison of Ollama vs llama.cpp.
enum LLMBackend: String, CaseIterable, Identifiable {
    case ollama
    case llamaCpp
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .llamaCpp: return "llama.cpp"
        }
    }
    
    /// Creates the appropriate provider for this backend.
    func makeProvider(configuration: LLMConfiguration) -> any LLMProvider {
        switch self {
        case .ollama:
            return OllamaLLMService(configuration: configuration.ollamaConfiguration)
        case .llamaCpp:
            return LlamaCppService(configuration: configuration.llamaCppConfiguration)
        }
    }
}