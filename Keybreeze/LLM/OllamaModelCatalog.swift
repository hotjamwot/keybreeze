import Foundation

/// Fetches installed model tags from Ollama (`GET /api/tags`), equivalent to `ollama list`.
enum OllamaModelCatalog {
    enum CatalogError: Error, LocalizedError {
        case unexpectedResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .unexpectedResponse:
                "Unexpected response from Ollama when listing models."
            case .httpStatus(let code):
                "Ollama model list failed with HTTP \(code)."
            }
        }
    }

    private struct TagsEnvelope: Decodable {
        struct ModelInfo: Decodable {
            let name: String
        }

        let models: [ModelInfo]
    }

    /// Sorted tags as returned by Ollama (e.g. `gemma2:2b`, `qwen2.5:3b`).
    static func fetchInstalledTags(
        configuration: OllamaConfiguration,
        urlSession: URLSession = .shared
    ) async throws -> [String] {
        let url = configuration.baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.unexpectedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw CatalogError.httpStatus(http.statusCode)
        }

        let envelope = try JSONDecoder().decode(TagsEnvelope.self, from: data)
        return envelope.models.map(\.name).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
