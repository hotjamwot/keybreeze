import Foundation

/// Connection settings for a local Ollama server (no model id here — that comes per request from `ModelOption`).
struct OllamaConfiguration: Equatable, Sendable {
    var baseURL: URL

    /// Defaults to IPv4 loopback so we avoid `localhost` → `::1` when Ollama listens on `127.0.0.1` only.
    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }
}
