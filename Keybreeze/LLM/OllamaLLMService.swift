import Foundation

/// Streams tokens from Ollama's `/api/generate` endpoint with cooperative cancellation.
///
/// Also provides static helpers to query the installed model catalog (`GET /api/tags`).
final class OllamaLLMService: LLMProvider, @unchecked Sendable {
    private let config: LLMConfig
    private let urlSession: URLSession
    private let lock = NSLock()
    private var activeStream: ActiveStream?

    private final class ActiveStream {
        let task: Task<Void, Error>
        init(task: Task<Void, Error>) { self.task = task }
    }

    init(config: LLMConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    func streamCompletion(
        prompt: String,
        model: String,
        modelOption: ModelOption,
        maxWords: Int,
        onToken: @escaping (String) -> Void
    ) async throws {
        cancel()

        let stream = ActiveStream(
            task: Task { [config, urlSession] in
                let url = config.ollamaBaseURL.appendingPathComponent("api/generate")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                // Compute num_predict from the word cap: ~4 tokens/word average, plus buffer.
                // This prevents the model from wasting tokens generating beyond what will be
                // displayed and keeps a tight bound for Ollama's prompt processing.
                let predictedTokens: Int = min(maxWords * 4 + 8, 128)
                // Stop sequences tell the model when to cease generation.
                // We only stop on double-newline (paragraph boundary) because:
                // 1. Punctuation (. ! ?) is part of natural text — stopping at them
                //    truncates multi-word completions mid-flow.
                // 2. Single \n stops the model from completing sentences naturally.
                // The word cap in PredictionEngine+PromptBuilder handles length.
                let stopSequences: [String] = ["\n\n"]
                let body = OllamaGenerateRequest(
                    model: model,
                    prompt: prompt,
                    stream: true,
                    temperature: modelOption.temperature,
                    top_p: modelOption.topP,
                    repeat_penalty: modelOption.repeatPenalty,
                    presence_penalty: modelOption.presencePenalty,
                    num_predict: predictedTokens,
                    stop: stopSequences
                )
                request.httpBody = try JSONEncoder().encode(body)

                let (bytes, response) = try await urlSession.bytes(for: request)
                try Self.validate(response: response)

                var lineIterator = bytes.lines.makeAsyncIterator()
                while let line = try await lineIterator.next() {
                    try Task.checkCancellation()
                    guard !line.isEmpty else { continue }
                    let chunk = try JSONDecoder().decode(OllamaGenerateStreamChunk.self, from: Data(line.utf8))
                    if let token = chunk.response, !token.isEmpty {
                        try Task.checkCancellation()
                        onToken(token)
                    }
                    if chunk.done == true {
                        break
                    }
                }
            }
        )

        lock.lock()
        activeStream = stream
        lock.unlock()

        defer {
            lock.lock()
            if activeStream === stream {
                activeStream = nil
            }
            lock.unlock()
        }

        try await stream.task.value
    }

    func cancel() {
        lock.lock()
        let stream = activeStream
        activeStream = nil
        lock.unlock()
        stream?.task.cancel()
    }

    // MARK: - Model catalog

    /// Fetches installed model tags from Ollama (`GET /api/tags`), equivalent to `ollama list`.
    static func fetchInstalledTags(
        baseURL: URL,
        urlSession: URLSession = .shared
    ) async throws -> [OllamaModelTag] {
        struct Response: Decodable {
            let models: [OllamaModelTag]
        }
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, _) = try await urlSession.data(from: url)
        return try JSONDecoder().decode(Response.self, from: data).models
    }

    /// Fetches and resolves installed tags into `ModelOption` values using the registry.
    static func fetchModelOptions(
        baseURL: URL,
        urlSession: URLSession = .shared
    ) async throws -> [ModelOption] {
        let tags = try await fetchInstalledTags(baseURL: baseURL, urlSession: urlSession)
        return tags.map { ModelRegistry.option(resolvingOllamaTag: $0.name) }
    }

    // MARK: - Private

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OllamaLLMError.unexpectedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OllamaLLMError.httpStatus(http.statusCode)
        }
    }
}

// MARK: - Errors

enum OllamaLLMError: Error, LocalizedError {
    case unexpectedResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "Unexpected response from Ollama."
        case .httpStatus(let code):
            if code == 404 {
                "Ollama returned HTTP 404 — unknown route or model tag not installed. Confirm Ollama is running and run `ollama pull <tag>` for the model you selected."
            } else {
                "Ollama returned HTTP \(code)."
            }
        }
    }
}

// MARK: - DTOs

/// A model tag returned by `GET /api/tags`.
struct OllamaModelTag: Decodable, Sendable, Identifiable {
    let name: String
    let modified_at: String?
    let size: Int64?

    var id: String { name }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let temperature: Double
    let top_p: Double
    let repeat_penalty: Double
    let presence_penalty: Double
    let num_predict: Int
    let stop: [String]
}

private struct OllamaGenerateStreamChunk: Decodable {
    let model: String?
    let response: String?
    let done: Bool?
}