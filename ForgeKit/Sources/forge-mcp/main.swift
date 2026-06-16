import Foundation
import ForgeKit

// B18 — forge-mcp: a Model Context Protocol (MCP) stdio server that lets external
// agents (Claude Code, Cline, even nanocoder) DRIVE a Forge project. Speaks
// newline-delimited JSON-RPC 2.0 on stdin/stdout. The project root is argv[1] (or
// the current directory).
//
// Tools: list_files, read_file (explore) · write_file (create/overwrite) ·
// run_command (shell in the project root: npm install / build / test) · get_errors
// (tsc --noEmit, classified through Forge's hardened ErrorClassifier so the agent
// gets the same deduped, noise-free errors the app's self-correction uses).
// Verified by piping JSON-RPC.

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
        ["name": "write_file",
         "description": "Create or overwrite a project file (path stays inside the project).",
         "inputSchema": ["type": "object",
                         "properties": ["path": ["type": "string", "description": "Project-relative path."],
                                        "contents": ["type": "string", "description": "Full file contents."]],
                         "required": ["path", "contents"]]],
        ["name": "run_command",
         "description": "Run a shell command in the project root (e.g. 'npm install', 'npm run build'). Returns the exit code + combined stdout/stderr.",
         "inputSchema": ["type": "object",
                         "properties": ["command": ["type": "string", "description": "Shell command."]],
                         "required": ["command"]]],
        ["name": "get_errors",
         "description": "Type-check the project (tsc --noEmit) and return deduped, classified build errors, or 'No errors'.",
         "inputSchema": ["type": "object", "properties": [String: Any]()]],
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

func writeFile(root: URL, path: String, contents: String) -> Bool {
    let target = root.appendingPathComponent(path).standardizedFileURL
    guard target.path.hasPrefix(root.standardizedFileURL.path) else { return false }   // stay inside the project
    do {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: target, atomically: true, encoding: .utf8)
        return true
    } catch { return false }
}

/// Run a command via a login shell (so node/npm are on PATH even when launched by a
/// GUI agent), in `dir`, with stdout+stderr merged into one stream.
func runShell(_ command: String, in dir: URL) -> (output: String, code: Int32) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/sh")
    proc.arguments = ["-lc", command]
    proc.currentDirectoryURL = dir
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do { try proc.run() } catch { return ("kunne ikke starte kommando: \(error)", -1) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()   // drains as it runs → no deadlock
    proc.waitUntilExit()
    return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
}

func getErrors(root: URL) -> String {
    let (output, _) = runShell("npx tsc --noEmit", in: root)
    let logs = output.split(separator: "\n", omittingEmptySubsequences: true)
        .map { LogLine(stream: .stderr, text: String($0)) }
    let report = ErrorClassifier().report(logs: logs, runtime: [])
    return report.isClean ? "No errors. ✓" : report.formatted()
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
        case "write_file":
            guard let path = args["path"] as? String, let contents = args["contents"] as? String else {
                fail(id: id, code: -32602, message: "write_file requires 'path' and 'contents'"); break
            }
            if writeFile(root: rootURL, path: path, contents: contents) {
                textResult(id: id, "Wrote \(path)")
            } else {
                fail(id: id, code: -32603, message: "Could not write \(path)")
            }
        case "run_command":
            guard let command = args["command"] as? String else {
                fail(id: id, code: -32602, message: "run_command requires a 'command'"); break
            }
            let (out, code) = runShell(command, in: rootURL)
            textResult(id: id, "exit \(code)\n\(out)")
        case "get_errors":
            textResult(id: id, getErrors(root: rootURL))
        default:
            fail(id: id, code: -32601, message: "Unknown tool: \(name)")
        }
    case "notifications/initialized", "initialized":
        break   // notifications take no response
    default:
        if !isNotification { fail(id: id, code: -32601, message: "Method not found: \(method)") }
    }
}
