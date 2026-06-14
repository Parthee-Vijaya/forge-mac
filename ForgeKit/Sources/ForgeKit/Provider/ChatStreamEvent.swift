import Foundation

/// A single streamed event from a chat model, normalized across providers so
/// the agent loop and artifact parser never see provider-specific shapes.
/// Errors are surfaced by throwing from the `AsyncThrowingStream`, not as a case.
public enum ChatStreamEvent: Sendable {
    case token(String)
    case done(reason: String?, promptTokens: Int?, completionTokens: Int?)
}
