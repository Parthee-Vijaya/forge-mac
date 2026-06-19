import XCTest
@testable import StormbreakerKit

final class ProviderErrorTests: XCTestCase {
    /// Dogfood (gemma, too big for RAM): LM Studio returns a 400 with an OpenAI-style
    /// error body. The description must surface the human message, not raw JSON.
    func testHTTPErrorExtractsOpenAIStyleMessage() {
        let body = #"{"error":{"message":"Failed to load model \"gemma-4\": insufficient system resources.","type":"server_error"}}"#
        let desc = ProviderError.http(status: 400, body: body).description
        XCTAssertTrue(desc.contains("insufficient system resources"), desc)
        XCTAssertFalse(desc.contains(#"{"error""#), "raw JSON should not leak: \(desc)")
    }

    func testHTTPErrorTopLevelMessage() {
        let body = #"{"message":"model not found"}"#
        XCTAssertTrue(ProviderError.http(status: 404, body: body).description.contains("model not found"))
    }

    func testHTTPErrorFallsBackToNonJSONBody() {
        let desc = ProviderError.http(status: 500, body: "internal error, not json").description
        XCTAssertTrue(desc.contains("internal error, not json"))
    }

    // MARK: - In-band stream errors (#8)

    /// In-band error frames (HTTP 200 + {"error":…}) must be detected so the turn
    /// fails loudly instead of ending empty.
    func testStreamErrorMessageDetectsObjectForm() {
        XCTAssertEqual(
            ProviderError.streamErrorMessage(in: #"{"error":{"message":"rate limited","code":429}}"#),
            "rate limited")
    }

    func testStreamErrorMessageDetectsStringForm() {
        // Ollama-style: {"error":"model not found"}
        XCTAssertEqual(ProviderError.streamErrorMessage(in: #"{"error":"model not found"}"#), "model not found")
    }

    func testStreamErrorMessageNilForNormalChunk() {
        XCTAssertNil(ProviderError.streamErrorMessage(in: #"{"choices":[{"delta":{"content":"hi"}}]}"#))
        XCTAssertNil(ProviderError.streamErrorMessage(in: "not json"))
        XCTAssertNil(ProviderError.streamErrorMessage(in: "[DONE]"))
    }

    func testStreamErrorDescriptionIsHumanReadable() {
        XCTAssertEqual(ProviderError.stream(message: "boom").description, "The model returned an error: boom")
    }
}
