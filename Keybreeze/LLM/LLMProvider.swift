import Foundation

/// Pluggable inference backend (Ollama now, llama.cpp later). Model id is per request so the registry can switch without new provider instances.
protocol LLMProvider {
    func streamCompletion(
        prompt: String,
        model: String,
        onToken: @escaping (String) -> Void
    ) async throws

    func cancel()
}
