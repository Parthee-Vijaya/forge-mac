import Foundation

/// User-configurable overrides on top of `ShellRules` (opencode `permission` parity).
/// Loaded from `~/.config/storm/permissions.json` (global) + `<project>/.forge/permissions.json`
/// (project); the lists are concatenated. Each list holds glob patterns (`*` = any
/// run) matched against the whole command.
///
/// Precedence when deciding a command:
///   1. a user `deny` match → deny (you can force-deny anything, e.g. `git push*`)
///   2. the catastrophic floor (ShellRules already said deny) → deny — NEVER loosened
///      by a user `allow`, so `rm -rf /` / `curl … | sh` stay blocked
///   3. a user `allow` match → allow (loosen the safe-but-asked space, e.g. `docker *`)
///   4. a user `ask` match → ask (tighten an otherwise-auto-allowed command)
///   5. otherwise the ShellRules default
public struct PermissionConfig: Sendable, Equatable {
    public var deny: [String]
    public var allow: [String]
    public var ask: [String]

    public init(deny: [String] = [], allow: [String] = [], ask: [String] = []) {
        self.deny = deny
        self.allow = allow
        self.ask = ask
    }

    public var isEmpty: Bool { deny.isEmpty && allow.isEmpty && ask.isEmpty }

    /// Apply the user overrides to a base verdict for `command`.
    public func override(_ base: ShellVerdict, command: String) -> ShellVerdict {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.matchesAny(deny, cmd) { return .deny }
        if base == .deny { return .deny }                 // catastrophic floor — not loosenable
        if Self.matchesAny(allow, cmd) { return .allow }
        if Self.matchesAny(ask, cmd) { return .ask }
        return base
    }

    /// Convenience: classify + override in one call.
    public func decide(_ command: String) -> ShellVerdict {
        override(ShellRules.classify(command), command: command)
    }

    // MARK: - Glob matching

    static func matchesAny(_ patterns: [String], _ command: String) -> Bool {
        patterns.contains { matches($0, command) }
    }

    /// Glob match: `*` means "any characters". The pattern is anchored at the start so
    /// `git push*` matches `git push origin main`; wrap in `*…*` for a substring match.
    static func matches(_ pattern: String, _ command: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return false }
        let escaped = p.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        guard let re = try? NSRegularExpression(pattern: "^" + escaped, options: [.caseInsensitive]) else { return false }
        let range = NSRange(command.startIndex..., in: command)
        return re.firstMatch(in: command, range: range) != nil
    }

    // MARK: - Loading

    /// `~/.config/storm/permissions.json` (or `$XDG_CONFIG_HOME/storm/...`).
    public static func globalURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        return base.appendingPathComponent("storm/permissions.json")
    }

    /// Merge global + project (lists concatenated; project rules are simply added).
    public static func load(projectRoot: URL?) -> PermissionConfig {
        var merged = parse(globalURL())
        if let root = projectRoot {
            let proj = parse(root.appendingPathComponent(".forge/permissions.json"))
            merged.deny += proj.deny
            merged.allow += proj.allow
            merged.ask += proj.ask
        }
        return merged
    }

    static func parse(_ url: URL) -> PermissionConfig {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PermissionConfig()
        }
        func list(_ key: String) -> [String] { (obj[key] as? [String])?.filter { !$0.isEmpty } ?? [] }
        return PermissionConfig(deny: list("deny"), allow: list("allow"), ask: list("ask"))
    }
}
