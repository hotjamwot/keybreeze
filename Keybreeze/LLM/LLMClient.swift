import Foundation
import OSLog

/// Simplified OpenAI-compatible LLM client.
/// Replaces the LLMProvider protocol + OllamaLLMService + LlamaCppService.
/// Uses a single HTTP endpoint for all backends (Ollama, llama.cpp server, LM Studio, etc.)
///
/// For Ollama: speaks /v1/chat/completions (streaming SSE) with messages array.
/// For llama.cpp: speaks /completion (streaming SSE) with raw prompt string and n_predict.
@MainActor
final class LLMClient: @unchecked Sendable {
    private let config: LLMConfig
    private let urlSession: URLSession
    private let log = Logger(subsystem: "app.keybreeze", category: "llm")
    private var activeTask: Task<Void, Never>?
    private let lock = NSLock()

    init(config: LLMConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    /// Stream completion tokens from the configured backend.
    /// - For Ollama: uses /v1/chat/completions with messages array.
    /// - For llama.cpp: uses /completion with raw prompt string and n_predict.
    func streamCompletion(
        prompt: String,
        systemPrompt: String? = nil,
        model: String,
        maxTokens: Int,
        temperature: Double = 0.0,
        topP: Double = 0.1,
        repeatPenalty: Double = 1.02,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        cancel()

        let url = config.apiBaseURL.appendingPathComponent(config.completionEndpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        switch config.backend {
        case .ollama:
            // OpenAI-style chat completions with messages array
            var messages: [OpenAIRequest.Message] = []
            if let systemPrompt, !systemPrompt.isEmpty {
                messages.append(.init(role: "system", content: systemPrompt))
            }
            messages.append(.init(role: "user", content: prompt))

            let body = OpenAIRequest(
                model: model,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                stream: true
            )
            request.httpBody = try JSONEncoder().encode(body)

        case .llamaCpp:
            // Raw completion endpoint — prompt is bare context text (no chat
            // template tokens). Stop token "<" prevents HTML/formatted output.
            // No "\n" stop token: newlines are common mid-word hesitation tokens
            // and would kill the stream before any useful text is generated.
            // The streaming gate in CompletionController handles display filtering.
            let body = LlamaCompletionRequest(
                prompt: prompt,
                nPredict: maxTokens,
                temperature: temperature,
                topP: topP,
                repeatPenalty: repeatPenalty,
                stream: true,
                stop: ["<"]
            )
            request.httpBody = try JSONEncoder().encode(body)
        }

        let task = Task { [weak self] in
            do {
                let (bytes, response) = try await urlSession.bytes(for: request)
                try Task.checkCancellation()

                var lineIterator = bytes.lines.makeAsyncIterator()
                while let line = try await lineIterator.next() {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data: "), line.count > 6 else { continue }
                    let json = String(line.dropFirst(6))
                    guard json != "[DONE]" else { break }

                    if let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: Data(json.utf8)) {
                        if let token = chunk.choices.first?.delta.content {
                            onToken(token)
                        }
                    } else if let llamaChunk = try? JSONDecoder().decode(LlamaCompletionChunk.self, from: Data(json.utf8)) {
                        // llama.cpp raw streaming uses content field directly
                        if let token = llamaChunk.content, !token.isEmpty {
                            onToken(token)
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.error("LLM stream error: \(error.localizedDescription)")
                }
            }
        }

        lock.lock()
        activeTask = task
        lock.unlock()

        defer {
            lock.lock()
            if activeTask == task { activeTask = nil }
            lock.unlock()
        }

        _ = try await task.value
    }

    func cancel() {
        lock.lock()
        let task = activeTask
        activeTask = nil
        lock.unlock()
        task?.cancel()
    }

    /// Scan GGUF models from directory.
    static func scanGGUFModels(directory: String) -> [ModelOption] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: directory)

        guard fm.fileExists(atPath: directory) else { return [] }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var models: [ModelOption] = []

        for case let fileURL as URL in enumerator {
            guard let resource = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resource.isRegularFile == true,
                  fileURL.pathExtension.lowercased() == "gguf" else { continue }

            let displayName = fileURL.deletingPathExtension().lastPathComponent
                .split(separator: "-")
                .map { String($0).capitalized }
                .joined(separator: " ")

            models.append(ModelOption(
                id: fileURL.path,
                displayName: displayName,
                ollamaId: "",
                ggufPath: fileURL.path,
                maxWords: 5,
                temperature: ModelOption.defaultTemperature,
                topP: ModelOption.defaultTopP,
                repeatPenalty: ModelOption.defaultRepeatPenalty,
                confidenceThreshold: ModelOption.defaultConfidenceThreshold
            ))
        }

        return models.sorted { $0.displayName < $1.displayName }
    }
}

// MARK: - Configuration

struct LLMConfig: Codable, Equatable, Sendable {
    var backend: LLMBackend = .ollama
    var ollamaBaseURL: URL = URL(string: "http://127.0.0.1:11434")!
    var llamaCppBaseURL: URL = URL(string: "http://127.0.0.1:11345")!
    var llamaCppModelsDirectory: String = "/Users/haydenjweal/Movies/PROJECTS/AI/local_LLMs/llamacpp_models"

    var apiBaseURL: URL {
        switch backend {
        case .ollama: return ollamaBaseURL
        case .llamaCpp: return llamaCppBaseURL
        }
    }

    /// The API endpoint path for the current backend.
    /// - Ollama: /v1/chat/completions (OpenAI-compatible messages array)
    /// - llama.cpp: /completion (raw text, no chat template)
    var completionEndpoint: String {
        switch backend {
        case .ollama: return "/v1/chat/completions"
        case .llamaCpp: return "/completion"
        }
    }
}

enum LLMBackend: String, CaseIterable, Identifiable, Codable, Sendable {
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

// MARK: - DTOs

// MARK: OpenAI /v1/chat/completions

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
        case topP = "top_p"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

// MARK: llama.cpp /completion (raw)

/// llama.cpp raw completion request — no chat template, just prompt text.
/// Uses n_predict instead of max_tokens for token limit.
/// Includes stop tokens and repeat_penalty for output quality control.
private struct LlamaCompletionRequest: Encodable {
    let prompt: String
    let nPredict: Int
    let temperature: Double
    let topP: Double
    let repeatPenalty: Double
    let stream: Bool
    let stop: [String]

    enum CodingKeys: String, CodingKey {
        case prompt, temperature, stream, stop
        case nPredict = "n_predict"
        case topP = "top_p"
        case repeatPenalty = "repeat_penalty"
    }
}

/// llama.cpp raw streaming chunk — content is a direct string, not a delta.
private struct LlamaCompletionChunk: Decodable {
    let content: String?
    let stop: Bool?
}
