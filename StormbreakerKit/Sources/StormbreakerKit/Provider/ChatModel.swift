import Foundation

/// A provider-agnostic chat message.
public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant }
    public let role: Role
    public let content: String
    /// Optional attached images as base64 data URLs (`data:image/png;base64,…`).
    /// Sent to vision-capable models (B4: screenshot/mockup → UI). Empty for
    /// text-only turns.
    public let imageDataURLs: [String]

    public init(role: Role, content: String, imageDataURLs: [String] = []) {
        self.role = role
        self.content = content
        self.imageDataURLs = imageDataURLs
    }

    /// Content safe to send to a provider. An empty / whitespace-only message is
    /// rejected by Anthropic (HTTP 400) and pollutes replayed history — and
    /// reasoning models routinely leave the visible text empty (they emit only
    /// `<think>` or an action artifact). Substitute a minimal placeholder so the
    /// user/assistant alternation stays valid across every provider.
    public var apiContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no content)" : content
    }
}

/// Generation knobs. `numCtx` is honored only by `OllamaNativeProvider` (the
/// native `/api/chat` path) — the OpenAI-compatible `/v1` path cannot set it.
public struct GenerationOptions: Sendable {
    public var temperature: Double
    public var numCtx: Int
    public var maxTokens: Int

    public init(temperature: Double = 0.2, numCtx: Int = 32_768, maxTokens: Int = 8_192) {
        self.temperature = temperature
        self.numCtx = numCtx
        self.maxTokens = maxTokens
    }
}

/// A streaming chat model. Implementations own their `URLSession` task and must
/// cancel it when the returned stream is terminated (via `onTermination`).
public protocol ChatModel: Sendable {
    func stream(
        messages: [ChatMessage],
        options: GenerationOptions
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}
