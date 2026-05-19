import Foundation
import OSLog

/// Communicates with a local `llama-server` via its `POST /completion` endpoint.
///
/// Uses **non-streaming** mode (`stream: false`) because llama.cpp's SSE mode
/// keeps the connection open indefinitely after all tokens have been delivered
/// (no terminating event), which makes Swift's `bytes.lines` iterator hang.
/// For short continuations (≤32 tokens) the latency difference is negligible.
///
/// The server must be loaded with a specific GGUF model at launch time, so the
/// `model` parameter in `streamCompletion(prompt:model:onToken:)` is unused.
final class LlamaCppService: LLMProvider, @unchecked Sendable {
    private let configuration: LlamaCppConfiguration
    private let urlSession: URLSession
    private let lock = NSLock()
    private var activeStream: ActiveStream?
    private let log = Logger(subsystem: "app.keybreeze", category: "llamacpp-svc")

    private final class ActiveStream {
        let task: Task<Void, Error>
        init(task: Task<Void, Error>) { self.task = task }
    }

    init(configuration: LlamaCppConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func streamCompletion(
        prompt: String,
        model: String,
        modelOption: ModelOption,
        onToken: @escaping (String) -> Void
    ) async throws {
        cancel()

let stream = ActiveStream(
            task: Task { [configuration, urlSession] in
                let url = configuration.baseURL.appendingPathComponent("completion")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                let body = LlamaCppCompletionRequest(
                    prompt: prompt,
                    stream: false,
                    n_predict: 16,
                    temperature: modelOption.temperature,
                    top_p: modelOption.topP,
                    repeat_penalty: modelOption.repeatPenalty,
                    cache_prompt: false
                )
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await urlSession.data(for: request)
                try Self.validate(response: response)

                let result = try JSONDecoder().decode(LlamaCppCompletionResponse.self, from: data)
                try Task.checkCancellation()

                if let content = result.content, !content.isEmpty {
                    // Deliver the full continuation as one token.
                    // The engine's `appendTokenRespectingWordCap` handles
                    // word-level truncation. This is far more reliable than
                    // SSE streaming given llama.cpp's event protocol quirks.
                    onToken(content)
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

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LlamaCppLLMError.unexpectedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw LlamaCppLLMError.httpStatus(http.statusCode)
        }
    }
}

// MARK: - Errors

enum LlamaCppLLMError: Error, LocalizedError {
    case unexpectedResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "Unexpected response from llama.cpp."
        case .httpStatus(let code):
            if code == 404 {
                "llama.cpp returned HTTP 404 — unknown route or model not loaded. Confirm llama-server is running."
            } else {
                "llama.cpp returned HTTP \(code)."
            }
        }
    }
}

// MARK: - Request / Response DTOs

/// Matches llama.cpp's `POST /completion` request body.
private struct LlamaCppCompletionRequest: Encodable {
    let prompt: String
    let stream: Bool
    let n_predict: Int
    let temperature: Double
    let top_p: Double
    let repeat_penalty: Double
    let cache_prompt: Bool
}

/// Matches the non-streaming response from `POST /completion`.
private struct LlamaCppCompletionResponse: Decodable {
    let content: String?
    let stop: Bool?
}