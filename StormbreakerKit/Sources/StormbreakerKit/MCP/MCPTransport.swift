import Foundation

/// Common interface for an MCP server connection, so the manager can hold a mix of
/// local (stdio) and remote (HTTP) servers behind one type.
public protocol MCPTransport: Sendable {
    var server: String { get }
    func start() async throws
    func listTools() async throws -> [MCPClient.Tool]
    func call(tool: String, arguments: [String: Any]) async throws -> String
    func shutdown()
}

extension MCPClient: MCPTransport {}   // stdio client already has these methods

/// MCP over the "Streamable HTTP" transport (opencode remote-MCP parity): JSON-RPC
/// 2.0 by HTTP POST. Handles a JSON *or* SSE (`data:`) response body and echoes the
/// `Mcp-Session-Id` the server hands back on initialize. `@unchecked Sendable` — the
/// lock guards the session id + request counter.
public final class MCPHTTPClient: MCPTransport, @unchecked Sendable {
    public let server: String
    private let url: URL
    private let headers: [String: String]
    private let lock = NSLock()
    private var sessionID: String?
    private var nextID = 1
    private static let timeout: TimeInterval = 30

    /// nil if `urlString` isn't a valid http(s) URL.
    public init?(server: String, url urlString: String, headers: [String: String]) {
        guard let u = URL(string: urlString), let s = u.scheme?.lowercased(), s == "http" || s == "https" else { return nil }
        self.server = server
        self.url = u
        self.headers = headers
    }

    public func start() async throws {
        _ = try await rpc("initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "stormbreaker", "version": "0.3.0"],
        ], captureSession: true)
        try await notify("notifications/initialized")
    }

    public func listTools() async throws -> [MCPClient.Tool] {
        let result = try await rpc("tools/list", [:])
        guard let dict = result as? [String: Any], let arr = dict["tools"] as? [[String: Any]] else { return [] }
        return arr.compactMap { t in
            guard let name = t["name"] as? String else { return nil }
            return MCPClient.Tool(server: server, name: name, description: (t["description"] as? String) ?? "")
        }
    }

    public func call(tool: String, arguments: [String: Any]) async throws -> String {
        let result = try await rpc("tools/call", ["name": tool, "arguments": arguments])
        // The MCP result is `{ content: [{type:"text", text:"…"}, …] }`.
        if let dict = result as? [String: Any], let content = dict["content"] as? [[String: Any]] {
            let texts = content.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let s = String(data: data, encoding: .utf8) { return s }
        return ""
    }

    public func shutdown() {
        guard let sid = lock.withLock({ sessionID }) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        URLSession.shared.dataTask(with: req).resume()   // fire-and-forget
    }

    // MARK: - JSON-RPC over HTTP

    private func nextRequestID() -> Int { lock.withLock { defer { nextID += 1 }; return nextID } }

    private func rpc(_ method: String, _ params: [String: Any], captureSession: Bool = false) async throws -> Any {
        let id = nextRequestID()
        let (data, resp) = try await post(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        if let http = resp as? HTTPURLResponse {
            if captureSession, let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
                lock.withLock { sessionID = sid }
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MCPError.server("HTTP \(http.statusCode) fra \(server)")
            }
        }
        guard let obj = Self.extractJSONRPC(data) else { throw MCPError.server("ugyldigt svar fra \(server)") }
        if let err = obj["error"] as? [String: Any] { throw MCPError.server(String(describing: err["message"] ?? err)) }
        return obj["result"] ?? [String: Any]()
    }

    private func notify(_ method: String) async throws {
        _ = try await post(["jsonrpc": "2.0", "method": method, "params": [String: Any]()])
    }

    private func post(_ body: [String: Any]) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url, timeoutInterval: Self.timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let sid = lock.withLock({ sessionID }) { req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: req)
    }

    /// Pull the JSON-RPC object from a plain-JSON body, or from an SSE stream's
    /// `data:` lines. nil if neither yields a JSON object.
    static func extractJSONRPC(_ data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        let text = String(decoding: data, as: UTF8.self)
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
               obj["result"] != nil || obj["error"] != nil || obj["jsonrpc"] != nil {
                return obj
            }
        }
        return nil
    }
}
