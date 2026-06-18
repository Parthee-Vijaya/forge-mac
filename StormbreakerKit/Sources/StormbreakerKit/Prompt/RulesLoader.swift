import Foundation

/// Loads per-project rules files into the system prompt. Reads the cross-tool
/// standard `AGENTS.md` (used by opencode / cursor / claude-code) AND Stormbreaker's own
/// `AI_RULES.md`; when both exist, both are included with `AI_RULES.md` last so
/// Stormbreaker's file wins ties. Shared by the app and the `storm` CLI so rules behave
/// identically in both (the CLI ignored rules before this).
public enum RulesLoader {
    public static func read(projectRoot: URL) -> String? {
        var parts: [String] = []
        for name in ["AGENTS.md", "AI_RULES.md"] {
            let url = projectRoot.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append("Project rules (\(name)):\n\(trimmed)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
