import Foundation
import OSLog

/// Simplified OpenAI-compatible LLM client.
/// Replaces the LLMProvider protocol + OllamaLLMService + LlamaCppService.
/// Uses a single HTTP endpoint for all backends (Ollama, llama.cpp server, LM Studio, etc.)
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
    func streamCompletion(
        prompt: String,
        systemPrompt: String? = nil,
        model: String,
        maxTokens: Int,
        temperature: Double = 0.35,
        topP: Double = 0.85,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        cancel()

        let url = config.apiBaseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

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

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, topP = "top_p", stream
        case maxTokens = "max_tokens"
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