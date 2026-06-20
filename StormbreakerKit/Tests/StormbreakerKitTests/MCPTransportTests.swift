import XCTest
@testable import StormbreakerKit

final class MCPTransportTests: XCTestCase {
    private func projectWithMCP(_ json: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".forge"), withIntermediateDirectories: true)
        try json.write(to: root.appendingPathComponent(".forge/.mcp.json"), atomically: true, encoding: .utf8)
        return root
    }

    func testLoadsRemoteAndStdioServers() throws {
        let root = try projectWithMCP(#"""
        { "mcpServers": {
            "fs":     { "command": "npx", "args": ["-y", "server-fs", "."] },
            "remote": { "url": "https://example.com/mcp", "headers": {"Authorization": "Bearer x"} },
            "off":    { "url": "https://nope.com/mcp", "enabled": false }
        } }
        """#)
        defer { try? FileManager.default.removeItem(at: root) }
        let configs = MCPManager.loadConfig(projectRoot: root)
        XCTAssertEqual(configs.count, 2, "disabled server is skipped")
        let remote = try XCTUnwrap(configs.first { $0.name == "remote" })
        XCTAssertTrue(remote.isRemote)
        XCTAssertEqual(remote.url, "https://example.com/mcp")
        XCTAssertEqual(remote.headers["Authorization"], "Bearer x")
        XCTAssertEqual(remote.display, "https://example.com/mcp")
        let stdio = try XCTUnwrap(configs.first { $0.name == "fs" })
        XCTAssertFalse(stdio.isRemote)
        XCTAssertEqual(stdio.display, "npx -y server-fs .")
        XCTAssertNil(configs.first { $0.name == "off" })
    }

    func testHTTPClientRejectsNonHTTPURL() {
        XCTAssertNil(MCPHTTPClient(server: "x", url: "ftp://example.com", headers: [:]))
        XCTAssertNil(MCPHTTPClient(server: "x", url: "not a url at all 🙂", headers: [:]))
        XCTAssertNotNil(MCPHTTPClient(server: "x", url: "https://example.com/mcp", headers: [:]))
    }

    func testExtractsJSONAndSSEResponses() {
        let plain = Data(#"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#.utf8)
        XCTAssertNotNil(MCPHTTPClient.extractJSONRPC(plain)?["result"])

        let sse = Data("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}\n\n".utf8)
        let obj = MCPHTTPClient.extractJSONRPC(sse)
        XCTAssertNotNil(obj?["result"])

        XCTAssertNil(MCPHTTPClient.extractJSONRPC(Data("garbage".utf8)))
    }
}
