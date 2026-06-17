import XCTest
@testable import ForgeKit

final class ModelConfigTests: XCTestCase {
    /// Gemini rides the OpenAI-compatible endpoint, so it must be an openAICompat
    /// config (→ OpenAICompatProvider) pointed at Google's compat base URL.
    func testGeminiUsesOpenAICompatEndpoint() {
        let cfg = ModelConfig.gemini(key: "k", model: "gemini-2.0-flash")
        XCTAssertEqual(cfg.kind, .openAICompat)
        XCTAssertEqual(cfg.source, .cloud)
        XCTAssertEqual(cfg.baseURL.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/openai/")
        XCTAssertEqual(cfg.apiKey, "k")
        XCTAssertTrue(ModelRouter.provider(for: cfg) is OpenAICompatProvider)
    }

    /// OpenRouter is an OpenAI-compatible gateway: openAICompat config at the
    /// OpenRouter base URL, carrying the optional attribution headers.
    func testOpenRouterConfig() {
        let cfg = ModelConfig.openRouter(key: "k", model: "openai/gpt-4o")
        XCTAssertEqual(cfg.kind, .openAICompat)
        XCTAssertEqual(cfg.source, .cloud)
        XCTAssertEqual(cfg.baseURL.absoluteString, "https://openrouter.ai/api/v1")
        XCTAssertEqual(cfg.apiKey, "k")
        XCTAssertEqual(cfg.modelID, "openai/gpt-4o")
        XCTAssertEqual(cfg.extraHeaders["X-Title"], "Forge")
        XCTAssertNotNil(cfg.extraHeaders["HTTP-Referer"])
        XCTAssertTrue(ModelRouter.provider(for: cfg) is OpenAICompatProvider)
    }

    /// Cost: local is free, known cloud prices compute, `:free` is free, unknown → nil.
    func testCost() {
        XCTAssertEqual(ModelConfig.lmStudio(model: "qwen").cost(promptTokens: 1000, completionTokens: 1000), 0)
        let gpt = ModelConfig.openAI(key: "k", model: "gpt-4o")          // 2.50 in / 10.00 out per 1M
        XCTAssertEqual(gpt.cost(promptTokens: 1_000_000, completionTokens: 1_000_000)!, 12.50, accuracy: 0.001)
        XCTAssertEqual(ModelConfig.openRouter(key: "k", model: "x/y:free").cost(promptTokens: 9, completionTokens: 9), 0)
        XCTAssertNil(ModelConfig.openRouter(key: "k", model: "obscure/unknown").cost(promptTokens: 9, completionTokens: 9))
    }
}
