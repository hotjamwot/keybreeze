import Foundation

/// Pluggable inference backend (Ollama now, llama.cpp later). Model id is per request so the registry can switch without new provider instances.
protocol LLMProvider {
    /// Stream completion tokens from the backend.
    /// - Parameters:
    ///   - prompt: The full prompt text to send.
    ///   - model: Provider-specific model identifier (Ollama tag or GGUF path).
    ///   - modelOption: Resolved model option with runtime parameters.
    ///   - maxWords: Maximum number of words the caller expects. Used to compute `num_predict`
    ///     so the model doesn't waste tokens generating beyond what will be shown.
    ///   - onToken: Called on each token received.
    func streamCompletion(
        prompt: String,
        model: String,
        modelOption: ModelOption,
        maxWords: Int,
        onToken: @escaping (String) -> Void
    ) async throws

    func cancel()
}
