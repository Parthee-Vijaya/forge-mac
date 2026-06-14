import XCTest
@testable import ForgeKit

final class ModelDiscoveryTests: XCTestCase {
    func testParsesOllamaTagsAndFiltersNonChat() {
        let json = Data("""
        {"models":[{"name":"qwen2.5-coder:14b"},{"name":"mistral-small3.2:24b"},{"name":"nomic-embed-text:latest"}]}
        """.utf8)
        let configs = ModelDiscovery.parseOllama(json)
        XCTAssertEqual(configs.map(\.modelID), ["qwen2.5-coder:14b", "mistral-small3.2:24b"])
        XCTAssertTrue(configs.allSatisfy { $0.source == .ollama && $0.kind == .ollamaNative })
    }

    func testParsesLMStudioModelsAndFiltersEmbeddings() {
        let json = Data("""
        {"object":"list","data":[
          {"id":"nvidia-nemotron-3-nano-30b-a3b-mlx"},
          {"id":"google/gemma-4-26b-a4b"},
          {"id":"text-embedding-nomic-embed-text-v1.5"}
        ]}
        """.utf8)
        let configs = ModelDiscovery.parseLMStudio(json)
        XCTAssertEqual(configs.map(\.modelID), ["nvidia-nemotron-3-nano-30b-a3b-mlx", "google/gemma-4-26b-a4b"])
        XCTAssertTrue(configs.allSatisfy { $0.source == .lmStudio && $0.kind == .openAICompat })
        XCTAssertTrue(configs.allSatisfy { $0.baseURL.absoluteString.contains(":1234") })
    }

    func testIDsAreUniqueAcrossSources() {
        XCTAssertNotEqual(ModelConfig.ollama(model: "x").id, ModelConfig.lmStudio(model: "x").id)
    }

    func testLiveDiscovery() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FORGE_RUN_INTEGRATION"] == "1",
            "set FORGE_RUN_INTEGRATION=1 (with Ollama/LM Studio running) for live discovery")
        let models = await ModelDiscovery.discoverLocal()
        XCTAssertFalse(models.isEmpty, "expected at least one local model")
    }
}
