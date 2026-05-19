import Foundation

/// Connection settings for a local llama.cpp server.
struct LlamaCppConfiguration: Equatable, Sendable {
    var baseURL: URL

    /// Directory where GGUF model files are stored.
    var modelsDirectory: String

    /// Defaults to IPv4 loopback so we avoid `localhost` → `::1` when llama.cpp listens on `127.0.0.1` only.
    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11345")!,
        modelsDirectory: String = "/Users/haydenjweal/Movies/PROJECTS/AI/local_LLMs/llamacpp_models"
    ) {
        self.baseURL = baseURL
        self.modelsDirectory = modelsDirectory
    }
}
