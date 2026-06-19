import XCTest
@testable import StormbreakerKit

final class ChatMessageTests: XCTestCase {
    /// An empty/whitespace assistant message must never reach a provider — Anthropic
    /// rejects it with HTTP 400. apiContent substitutes a placeholder.
    func testApiContentPlaceholderForEmpty() {
        XCTAssertEqual(ChatMessage(role: .assistant, content: "").apiContent, "(no content)")
        XCTAssertEqual(ChatMessage(role: .assistant, content: "   \n\t").apiContent, "(no content)")
    }

    func testApiContentPreservesRealContent() {
        XCTAssertEqual(ChatMessage(role: .assistant, content: "hello").apiContent, "hello")
        // Leading/trailing whitespace around real content is preserved as-is.
        XCTAssertEqual(ChatMessage(role: .user, content: "  hi  ").apiContent, "  hi  ")
    }
}
