import Foundation

/// Loads per-project rules files into the system prompt. Reads, in order, Claude
/// Code's `CLAUDE.md`, the cross-tool standard `AGENTS.md` (opencode / cursor), and
/// Stormbreaker's own `AI_RULES.md`. All that exist are included, listed last-wins so
/// `AI_RULES.md` (native) beats `AGENTS.md` beats `CLAUDE.md` on conflicts. Shared by
/// the app and the `storm` CLI so rules behave identically in both — and a project
/// authored for Claude Code / opencode works in Stormbreaker unchanged.
public enum RulesLoader {
    public static func read(projectRoot: URL) -> String? {
        var parts: [String] = []
        for name in ["CLAUDE.md", "AGENTS.md", "AI_RULES.md"] {
            let url = projectRoot.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append("Project rules (\(name)):\n\(trimmed)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
