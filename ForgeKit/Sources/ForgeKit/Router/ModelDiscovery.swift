import Foundation

/// Discovers locally-served chat models from Ollama (:11434 `/api/tags`) and
/// LM Studio (:1234 `/v1/models`). Each probe has a short timeout, so a server
/// that isn't running is simply skipped. Embedding/rerank models are filtered
/// out (they can't drive the agent).
public enum ModelDiscovery {
    public static func discoverLocal(
        ollamaBase: URL = URL(string: "http://localhost:11434")!,
        lmStudioBase: URL = URL(string: "http://localhost:1234/v1")!
    ) async -> [ModelConfig] {
        async let ollama = ollamaModels(base: ollamaBase)
        async let lmStudio = lmStudioModels(base: lmStudioBase)
        return await ollama + lmStudio
    }

    static func ollamaModels(base: URL) async -> [ModelConfig] {
        guard let data = try? await get(base.appendingPathComponent("api/tags")) else { return [] }
        return parseOllama(data)
    }

    static func lmStudioModels(base: URL) async -> [ModelConfig] {
        guard let data = try? await get(base.appendingPathComponent("models")) else { return [] }
        return parseLMStudio(data)
    }

    // MARK: - Pure parsing (unit-testable)

    static func parseOllama(_ data: Data) -> [ModelConfig] {
        struct Response: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return decoded.models.map(\.name)
            .filter { !isNonChat($0) }
            .map { ModelConfig.ollama(model: $0) }
    }

    static func parseLMStudio(_ data: Data) -> [ModelConfig] {
        struct Response: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return decoded.data.map(\.id)
            .filter { !isNonChat($0) }
            .map { ModelConfig.lmStudio(model: $0) }
    }

    static func isNonChat(_ id: String) -> Bool {
        let lower = id.lowercased()
        return ["embed", "embedding", "rerank", "bge-", "whisper", "clip"].contains { lower.contains($0) }
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.transport("model discovery failed")
        }
        return data
    }
}
