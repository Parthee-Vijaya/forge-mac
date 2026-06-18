import XCTest
@testable import StormbreakerKit

/// End-to-end proof of the process layer against real npm/vite. Slow (a real
/// `npm install`), so gated behind STORM_RUN_INTEGRATION=1:
///
///   STORM_RUN_INTEGRATION=1 swift test --filter DevServerIntegrationTests
final class DevServerIntegrationTests: XCTestCase {
    func testStartsServesAndStopsDevServer() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["STORM_RUN_INTEGRATION"] == "1",
            "set STORM_RUN_INTEGRATION=1 to run the slow npm/vite integration test"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("storm-it-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = ProjectWorkspace(root: root)
        try await TemplateInstaller().install(into: workspace)

        let manager = DevServerManager(workspace: workspace)
        let url = try await manager.start(timeout: .seconds(300))
        XCTAssertEqual(url.scheme, "http")
        XCTAssertNotNil(url.port)

        // The server should actually serve the index HTML with the React root.
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("id=\"root\""))

        await manager.shutdown()
        let readyAfter = await manager.serverReadyURL
        XCTAssertNil(readyAfter)
    }
}
