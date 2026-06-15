import Foundation

// B18 — forge-mcp: a minimal Model Context Protocol (MCP) stdio server that exposes
// a Forge project's files to external agents (Claude Code, Cline, …). Speaks
// newline-delimited JSON-RPC 2.0 on stdin/stdout. The project root is argv[1] (or
// the current directory).
//
// START: implements the MCP handshake (initialize), tools/list, and tools/call for
// read-only filesystem tools (list_files, read_file). Reuses Forge's project-dir
// concept via plain Foundation (sync) to stay Swift-6-clean. Write access and
// run_command (over DevServerManager) are the remaining work — read tools first so
// an external agent can safely explore a project. Verified by piping JSON-RPC.

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func reply(id: Any, result: [String: Any]) {
    emit(["jsonrpc": "2.0", "id": id, "result": result])
}

func fail(id: Any, code: Int, message: String) {
    emit(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func toolDefinitions() -> [[String: Any]] {
    [
        ["name": "list_files",
         "description": "List the project's source files (node_modules/.git/dist excluded).",
         "inputSchema": ["type": "object", "properties": [String: Any]()]],
        ["name": "read_file",
         "description": "Read a project file's contents.",
         "inputSchema": ["type": "object",
                         "properties": ["path": ["type": "string", "description": "Project-relative path."]],
                         "required": ["path"]]],
    ]
}

func listFiles(root: URL) -> [String] {
    let skip: Set<String> = ["node_modules", ".git", "dist", ".forge", ".next", "out", ".DS_Store"]
    let base = root.resolvingSymlinksInPath()
    let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
    guard let en = FileManager.default.enumerator(
        at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
    var out: [String] = []
    for case let url as URL in en {
        if skip.contains(url.lastPathComponent) { en.skipDescendants(); continue }
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else { continue }
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            out.append(String(path.dropFirst(prefix.count)))
        }
    }
    return out.sorted()
}

func readFile(root: URL, path: String) -> String? {
    let target = root.appendingPathComponent(path).standardizedFileURL
    // Refuse to read outside the project root.
    guard target.path.hasPrefix(root.standardizedFileURL.path) else { return nil }
    return try? String(contentsOf: target, encoding: .utf8)
}

func textResult(id: Any, _ text: String) {
    reply(id: id, result: ["content": [["type": "text", "text": text]]])
}

// MARK: - Main loop

let rootURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

    let method = msg["method"] as? String ?? ""
    let id = msg["id"] ?? NSNull()
    let isNotification = msg["id"] == nil

    switch method {
    case "initialize":
        reply(id: id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "forge-mcp", "version": "0.1.0"],
        ])
    case "tools/list":
        reply(id: id, result: ["tools": toolDefinitions()])
    case "tools/call":
        let params = msg["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "list_files":
            textResult(id: id, listFiles(root: rootURL).joined(separator: "\n"))
        case "read_file":
            guard let path = args["path"] as? String else {
                fail(id: id, code: -32602, message: "read_file requires a 'path' argument"); break
            }
            if let contents = readFile(root: rootURL, path: path) {
                textResult(id: id, contents)
            } else {
                fail(id: id, code: -32603, message: "Could not read \(path)")
            }
        default:
            fail(id: id, code: -32601, message: "Unknown tool: \(name)")
        }
    case "notifications/initialized", "initialized":
        break   // notifications take no response
    default:
        if !isNotification { fail(id: id, code: -32601, message: "Method not found: \(method)") }
    }
}
