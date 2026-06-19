import Foundation

/// Anthropic Messages-API shim. The system prompt is a TOP-LEVEL `system`
/// field (not a system-role message), so we split it out of the message array.
/// Streams `content_block_delta` text deltas.
public struct AnthropicProvider: ChatModel {
    let baseURL: URL
    let apiKey: String
    let modelID: String
    let anthropicVersion: String

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiKey: String,
        modelID: String,
        anthropicVersion: String = "2023-06-01"
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.anthropicVersion = anthropicVersion
    }

    public func stream(messages: [ChatMessage], options: GenerationOptions)
        -> AsyncThrowingStream<ChatStreamEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(provider: "Anthropic") }
                    let systemText = messages.filter { $0.role == .system }
                        .map(\.content).joined(separator: "\n\n")
                    let conversation = messages.filter { $0.role != .system }
                        .map { Request.Message(role: $0.role.rawValue, content: $0.apiContent) }

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    let body = Request(
                        model: modelID,
                        max_tokens: options.maxTokens,
                        system: systemText.isEmpty ? nil : systemText,
                        messages: conversation,
                        stream: true)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try await ensureOK(response, bytes: bytes)

                    let decoder = JSONDecoder()
                    for try await line in SSELineReader(bytes) {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, let data = payload.data(using: .utf8),
                              let event = try? decoder.decode(StreamEvent.self, from: data) else { continue }
                        switch event.type {
                        case "content_block_delta":
                            if let text = event.delta?.text, !text.isEmpty {
                                continuation.yield(.token(text))
                            }
                        case "message_stop":
                            continuation.yield(.done(reason: "stop", promptTokens: nil, completionTokens: nil))
                        case "error":
                            throw ProviderError.http(status: 0, body: event.error?.message ?? "Anthropic stream error")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
        let stream: Bool
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct StreamEvent: Decodable {
        struct Delta: Decodable { let text: String? }
        struct ErrorInfo: Decodable { let message: String? }
        let type: String
        let delta: Delta?
        let error: ErrorInfo?
    }
}
