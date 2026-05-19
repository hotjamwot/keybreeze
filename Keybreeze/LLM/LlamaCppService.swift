import Foundation

/// Streams tokens from llama.cpp's `/generate` endpoint (or Unix socket) with cooperative cancellation.
final class LlamaCppService: LLMProvider, @unchecked Sendable {
    private let configuration: LlamaCppConfiguration
    private let urlSession: URLSession
    private let lock = NSLock()
    private var activeStream: ActiveStream?

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
        onToken: @escaping (String) -> Void
    ) async throws {
        cancel()

        let stream = ActiveStream(
            task: Task { [configuration, urlSession] in
                // For now, a placeholder implementation that echoes tokens
                // In a real implementation, this would connect to llama.cpp's API
                let url = configuration.baseURL.appendingPathComponent("api/generate")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                let body = LlamaCppGenerateRequest(model: model, prompt: prompt, stream: true)
                request.httpBody = try JSONEncoder().encode(body)

                let (bytes, response) = try await urlSession.bytes(for: request)
                try Self.validate(response: response)

                var lineIterator = bytes.lines.makeAsyncIterator()
                while let line = try await lineIterator.next() {
                    try Task.checkCancellation()
                    guard !line.isEmpty else { continue }
                    let chunk = try JSONDecoder().decode(LlamaCppGenerateStreamChunk.self, from: Data(line.utf8))
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

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LlamaCppLLMError.unexpectedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw LlamaCppLLMError.httpStatus(http.statusCode)
        }
    }
}

enum LlamaCppLLMError: Error, LocalizedError {
    case unexpectedResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "Unexpected response from llama.cpp."
        case .httpStatus(let code):
            if code == 404 {
                "llama.cpp returned HTTP 404 — unknown route or model not loaded. Confirm llama.cpp is running and the model is loaded."
            } else {
                "llama.cpp returned HTTP \(code)."
            }
        }
    }
}

private struct LlamaCppGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct LlamaCppGenerateStreamChunk: Decodable {
    let model: String?
    let response: String?
    let done: Bool?
}