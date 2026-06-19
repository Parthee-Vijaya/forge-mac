import Foundation

/// Loads user-authored slash commands from two layers (project overrides global,
/// matched by id): `~/.config/storm/commands/*.md` and `<project>/.forge/commands/*.md`.
/// Mirrors `SkillStore`. There are no built-in commands — the slash router already
/// owns the built-in verbs (/diff, /model, …); this is purely the user-extensible set.
public enum CommandStore {
    /// `~/.config/storm/commands` (or `$XDG_CONFIG_HOME/storm/commands`).
    public static func globalDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        return base.appendingPathComponent("storm/commands")
    }

    /// Global + project commands, deduped by id (project wins), sorted by name.
    public static func load(projectRoot: URL? = nil) -> [StormCommand] {
        var byID: [String: StormCommand] = [:]
        for c in loadDir(globalDir(), origin: .global) { byID[c.id] = c }
        if let root = projectRoot {
            for c in loadDir(root.appendingPathComponent(".forge/commands"), origin: .project) { byID[c.id] = c }
        }
        return byID.values.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    public static func find(_ name: String, in commands: [StormCommand]) -> StormCommand? {
        let t = name.lowercased()
        return commands.first { $0.id == t }
    }

    static func loadDir(_ dir: URL, origin: StormCommand.Origin) -> [StormCommand] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return StormCommand.parse(text, id: url.deletingPathExtension().lastPathComponent, origin: origin)
            }
    }
}
