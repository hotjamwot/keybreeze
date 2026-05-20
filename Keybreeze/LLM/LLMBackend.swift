import Foundation

/// Available inference backends.
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
}

/// Flat shared configuration for inference backends.
///
/// Replaces the exploded `LLMConfiguration` + `OllamaConfiguration` +
/// `LlamaCppConfiguration` pattern with a single struct. Backend-specific
/// overrides live as optional fields; the active subset is determined by
/// `backend`.
struct LLMConfig: Equatable, Sendable {
    var backend: LLMBackend = .ollama

    // -- Shared (used by both backends) --

    /// IPv4 loopback avoids `localhost` → `::1` issues when the server
    /// listens on `127.0.0.1` only.
    var ollamaBaseURL: URL = URL(string: "http://127.0.0.1:11434")!

    // -- llama.cpp specific --

    var llamaCppBaseURL: URL = URL(string: "http://127.0.0.1:11345")!
    var llamaCppModelsDirectory: String = "/Users/haydenjweal/Movies/PROJECTS/AI/local_LLMs/llamacpp_models"
}