import Foundation

/// Failures from a chat-model provider.
public enum ProviderError: Error, Sendable, Equatable {
    case missingAPIKey(provider: String)
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)
    /// An error delivered IN-BAND on a 200 response (an `{"error":…}` frame in the
    /// SSE/JSON stream) — common from OpenRouter/LM Studio/Ollama. Without this the
    /// frame was silently skipped and the turn ended empty.
    case stream(message: String)
}

extension ProviderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingAPIKey(let provider):
            "Missing API key for \(provider). Set STORM_CLOUD_API_KEY."
        case .http(let status, let body):
            "Model request failed (HTTP \(status)): \(Self.humanMessage(from: body))"
        case .decoding(let message):
            "Could not decode the model response: \(message)"
        case .transport(let message):
            "Network error talking to the model: \(message)"
        case .stream(let message):
            "The model returned an error: \(message)"
        }
    }

    /// If `payload` is an in-band error frame (`{"error":{"message":…}}` or
    /// `{"error":"…"}`), return its message; otherwise nil (a normal data chunk).
    static func streamErrorMessage(in payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] else { return nil }
        if let dict = error as? [String: Any], let message = dict["message"] as? String, !message.isEmpty {
            return String(message.prefix(300))
        }
        if let message = error as? String, !message.isEmpty { return String(message.prefix(300)) }
        return "ukendt fejl fra modellen"
    }

    /// Pull the human message out of an OpenAI-style error body
    /// (`{"error":{"message":"…"}}`, also used by LM Studio/Ollama) so a beginner sees
    /// e.g. "Failed to load model … insufficient system resources" instead of raw JSON.
    /// Falls back to the trimmed body.
    static func humanMessage(from body: String) -> String {
        let fallback = String(body.prefix(300))
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return fallback }
        if let error = obj["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return String(message.prefix(300))
        }
        if let message = obj["message"] as? String, !message.isEmpty {
            return String(message.prefix(300))
        }
        return fallback
    }
}
