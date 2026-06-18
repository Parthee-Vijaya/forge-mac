import XCTest
@testable import StormbreakerKit

/// The whole walking skeleton, headless: real Ollama model → artifact parser →
/// file writes → npm install → vite → live URL. Gated behind
/// STORM_RUN_INTEGRATION=1 (needs Ollama running with qwen2.5-coder:14b).
final class FullLoopLiveTests: XCTestCase {
    func testEndToEndBuildsAndServesGeneratedApp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["STORM_RUN_INTEGRATION"] == "1",
            "set STORM_RUN_INTEGRATION=1 (and run Ollama) to run the full end-to-end test"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("storm-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = ProjectWorkspace(root: root)
        try await TemplateInstaller().install(into: workspace)

        let devServer = DevServerManager(workspace: workspace)
        let process = StormbreakerProcessLayer(workspace: workspace, devServer: devServer)
        let collector = ErrorCollector(devServer: devServer)

        let config = ModelConfig.localDefault
        let deps = AgentLoop.Dependencies(
            provider: ModelRouter.provider(for: config),
            options: ModelRouter.options(for: config),
            process: process,
            projectContext: { nil },
            collectErrors: { await collector.collect() },
            onTurnStart: { await collector.reset() },
            settleDelay: .seconds(3),
            maxRepairAttempts: 1)

        var previewURL: URL?
        var reachedClean = false
        var lastFailure: String?
        let prompt = """
        Replace src/App.tsx with a centered page: a big heading that says "Hello Stormbreaker" and a \
        button labeled "Count" that increments a number displayed below it. Keep it black and white.
        """
        for await event in AgentLoop(deps).run(userPrompt: prompt, history: []) {
            switch event {
            case .previewReady(let url): previewURL = url
            case .state(.clean): reachedClean = true
            case .state(.failed(let reason)): lastFailure = reason
            default: break
            }
        }

        // The server should be serving the generated app.
        if let url = previewURL {
            let (data, response) = try await URLSession.shared.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("id=\"root\""))
        }
        await devServer.shutdown()

        XCTAssertNotNil(previewURL, "no preview URL — pipeline did not reach a running server (failure: \(lastFailure ?? "none"))")

        // The model should have replaced the placeholder template App.
        let app = try await workspace.readFile("src/App.tsx")
        XCTAssertFalse(
            app.contains("Describe the app you want to build"),
            "App.tsx still has the template placeholder — model output was not applied")
        print("[FullLoopLive] reachedClean=\(reachedClean) failure=\(lastFailure ?? "none")")
        print("[FullLoopLive] App.tsx head:\n\(app.prefix(600))")
    }
}
