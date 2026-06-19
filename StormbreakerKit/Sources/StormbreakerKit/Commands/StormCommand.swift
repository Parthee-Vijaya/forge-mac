import Foundation

/// A user-authored slash command (opencode parity). Drop a markdown file in
/// `~/.config/storm/commands/<name>.md` (global) or `<project>/.forge/commands/<name>.md`
/// (project) and invoke it as `/<name> [args]` in the TUI. The body is a prompt
/// template expanded with:
///   - `$ARGUMENTS` → the text typed after the command name
///   - `` !`shell` `` → the stdout of a shell command (context-gathering, e.g. `!`git diff`)
///   - `@path`       → the contents of a project file, inlined as a fenced block
///
/// Optional `---` frontmatter: `description`, `mode` (build|plan). The filename is the
/// command name unless `id:` overrides it.
public struct StormCommand: Sendable, Identifiable, Equatable {
    public enum Origin: String, Sendable, Equatable { case global, project }

    public var id: String          // the slash name, e.g. "review"
    public var description: String
    public var mode: AgentLoop.Mode
    public var template: String
    public var origin: Origin

    public init(id: String, description: String = "", mode: AgentLoop.Mode = .build,
                template: String, origin: Origin = .project) {
        self.id = id
        self.description = description
        self.mode = mode
        self.template = template
        self.origin = origin
    }

    /// Expand the template into a prompt. `runShell` returns a command's stdout, or
    /// nil if it must not run (the caller gates it); `readFile` returns a project
    /// file's contents, or nil if absent. Both are async; substitutions apply in
    /// order ($ARGUMENTS → shells → files).
    public func expand(
        arguments: String,
        runShell: @Sendable (String) async -> String?,
        readFile: @Sendable (String) async -> String?
    ) async -> String {
        var out = template.replacingOccurrences(
            of: "$ARGUMENTS", with: arguments.trimmingCharacters(in: .whitespacesAndNewlines))
        out = await Self.expandShell(out, runShell: runShell)
        out = await Self.expandFiles(out, readFile: readFile)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Expansion internals

    /// Replace each `` !`cmd` `` with the command's stdout (or a skipped-note).
    static func expandShell(_ text: String, runShell: (String) async -> String?) async -> String {
        guard let re = try? NSRegularExpression(pattern: "!`([^`]+)`") else { return text }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = text
        // Apply last-to-first so earlier match ranges (computed on the original) stay
        // valid against the mutated string.
        for m in matches.reversed() {
            let cmd = ns.substring(with: m.range(at: 1))
            let output = (await runShell(cmd))?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "[sprang kommandoen over: \(cmd)]"
            if let r = Range(m.range, in: result) { result.replaceSubrange(r, with: output) }
        }
        return result
    }

    /// Replace each `@path` (path-like token) with the file's contents as a fenced
    /// block. Tokens whose file doesn't exist are left untouched (literal `@`).
    static func expandFiles(_ text: String, readFile: (String) async -> String?) async -> String {
        guard let re = try? NSRegularExpression(pattern: #"@([A-Za-z0-9_./\-]+)"#) else { return text }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = text
        for m in matches.reversed() {
            let path = ns.substring(with: m.range(at: 1))
            guard let contents = await readFile(path) else { continue }   // leave literal @token
            let block = "\n\n\(path):\n```\n\(contents)\n```\n"
            if let r = Range(m.range, in: result) { result.replaceSubrange(r, with: block) }
        }
        return result
    }

    /// Parse a command file: optional `---` frontmatter (description, mode, id) + a
    /// markdown body that becomes the template. nil if the body is empty.
    public static func parse(_ text: String, id fallbackID: String, origin: Origin) -> StormCommand? {
        var meta: [String: String] = [:]
        var body = text
        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closeIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<closeIdx] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { meta[key] = value }
            }
            body = closeIdx + 1 < lines.count ? lines[(closeIdx + 1)...].joined(separator: "\n") : ""
        }
        let template = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return nil }
        let id = (meta["id"].map { $0.isEmpty ? fallbackID : $0 }) ?? fallbackID
        return StormCommand(
            id: id.lowercased(),
            description: meta["description"] ?? "",
            mode: meta["mode"]?.lowercased() == "plan" ? .plan : .build,
            template: template,
            origin: origin)
    }
}
