import Foundation

/// Failures from a chat-model provider.
public enum ProviderError: Error, Sendable, Equatable {
    case missingAPIKey(provider: String)
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)
}

extension ProviderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingAPIKey(let provider):
            "Missing API key for \(provider). Set FORGE_CLOUD_API_KEY."
        case .http(let status, let body):
            "Model request failed (HTTP \(status)): \(body.prefix(300))"
        case .decoding(let message):
            "Could not decode the model response: \(message)"
        case .transport(let message):
            "Network error talking to the model: \(message)"
        }
    }
}
