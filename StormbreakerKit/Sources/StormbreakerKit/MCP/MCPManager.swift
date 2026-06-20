import Foundation

/// Loads `<project>/.forge/.mcp.json`, starts the configured MCP servers, aggregates
/// their tools, and routes the agent's tool calls. Best-effort: a server that fails
/// to start is skipped (its tools just won't be offered). `@unchecked Sendable` via
/// an internal lock guarding the client/tool maps.
public final class MCPManager: @unchecked Sendable {
    public struct ServerConfig: Sendable, Equatable {
        public let name: String
        public let command: String              // stdio (empty for a remote server)
        public let args: [String]
        public let env: [String: String]
        public let url: String?                 // remote (http/sse) — nil for stdio
        public let headers: [String: String]    // remote auth headers
        public let enabled: Bool
        public var isRemote: Bool { url != nil }
        /// A one-line description of what this server runs/connects to (for the C6 prompt).
        public var display: String { url ?? ([command] + args).joined(separator: " ") }
    }

    private let lock = NSLock()
    private var clients: [String: any MCPTransport] = [:]
    private var tools: [MCPClient.Tool] = []

    public init() {}

    /// Parse `.forge/.mcp.json` (`{"mcpServers": {name: {command, args, env}}}`,
    /// nanocoder-compatible). `${VAR}` in env values is expanded from the environment.
    public static func loadConfig(projectRoot: URL) -> [ServerConfig] {
        let path = projectRoot.appendingPathComponent(".forge/.mcp.json")
        guard let data = try? Data(contentsOf: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = obj["mcpServers"] as? [String: [String: Any]] else { return [] }
        let environment = ProcessInfo.processInfo.environment
        return servers.compactMap { name, cfg in
            let enabled = (cfg["enabled"] as? Bool) ?? true
            guard enabled else { return nil }
            var env: [String: String] = [:]
            for (k, v) in (cfg["env"] as? [String: String]) ?? [:] {
                env[k] = expandEnv(v, environment)
            }
            // Remote server: a `url` (optionally `headers`), nanocoder/opencode shape.
            if let url = (cfg["url"] as? String) ?? (cfg["uri"] as? String), !url.isEmpty {
                var headers: [String: String] = [:]
                for (k, v) in (cfg["headers"] as? [String: String]) ?? [:] { headers[k] = expandEnv(v, environment) }
                return ServerConfig(name: name, command: "", args: [], env: env,
                                    url: expandEnv(url, environment), headers: headers, enabled: true)
            }
            // Local (stdio) server: a `command` (+ args).
            guard let command = cfg["command"] as? String, !command.isEmpty else { return nil }
            return ServerConfig(name: name, command: command, args: (cfg["args"] as? [String]) ?? [],
                                env: env, url: nil, headers: [:], enabled: true)
        }
    }

    private static func expandEnv(_ value: String, _ environment: [String: String]) -> String {
        var out = value
        for (k, v) in environment {
            out = out.replacingOccurrences(of: "${\(k)}", with: v)
        }
        return out
    }

    /// Start every configured server and collect its tools (best-effort, concurrent).
    public func start(projectRoot: URL) async {
        let configs = Self.loadConfig(projectRoot: projectRoot)
        await withTaskGroup(of: (any MCPTransport, [MCPClient.Tool])?.self) { group in
            for cfg in configs {
                group.addTask {
                    let client: any MCPTransport
                    if let url = cfg.url {
                        guard let http = MCPHTTPClient(server: cfg.name, url: url, headers: cfg.headers) else { return nil }
                        client = http
                    } else {
                        client = MCPClient(server: cfg.name, command: cfg.command,
                                           args: cfg.args, env: cfg.env, cwd: projectRoot)
                    }
                    do {
                        try await client.start()
                        return (client, try await client.listTools())
                    } catch {
                        client.shutdown(); return nil
                    }
                }
            }
            for await result in group {
                guard let (client, t) = result else { continue }
                lock.withLock { clients[client.server] = client; tools.append(contentsOf: t) }
            }
        }
    }

    public var availableTools: [MCPClient.Tool] {
        lock.withLock { tools }
    }

    public var isEmpty: Bool { availableTools.isEmpty }

    /// A prompt section listing the tools the model may call, and how. Empty when no
    /// MCP servers are configured (so the base prompt is unchanged).
    public func promptSection() -> String? {
        let t = availableTools
        guard !t.isEmpty else { return nil }
        let list = t.map { "- `\($0.server)` / `\($0.name)`: \($0.description)" }.joined(separator: "\n")
        return """
        EXTERNAL TOOLS (MCP)
        You can call external tools. If the user needs information or an action that only a
        tool can provide, you MUST call the tool FIRST — never guess or invent a value a tool
        can give you.

        To call a tool, emit ONLY a forgeArtifact containing the mcp action (write NO files in
        that turn) and STOP. The result is fed back to you, then you continue the build:
        <forgeArtifact id="tool" title="Calling tool">
        <forgeAction type="mcp" server="<server>" tool="<tool>">{ "arg": "value" }</forgeAction>
        </forgeArtifact>

        The mcp action MUST be inside a <forgeArtifact>, exactly like file actions — a bare
        <forgeAction> outside an artifact is ignored. Use {} as the body if the tool takes no
        arguments.

        Available tools:
        \(list)
        """
    }

    public func call(server: String, tool: String, arguments: [String: Any]) async -> String {
        let client = lock.withLock { clients[server] }
        guard let client else { return "Fejl: ukendt MCP-server '\(server)'." }
        do { return try await client.call(tool: tool, arguments: arguments) }
        catch { return "Fejl ved \(server)/\(tool): \(error)" }
    }

    public func shutdownAll() {
        let cs: [any MCPTransport] = lock.withLock {
            let c = Array(clients.values); clients.removeAll(); tools.removeAll(); return c
        }
        cs.forEach { $0.shutdown() }
    }
}
