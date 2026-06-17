import Foundation
import ForgeKit

// ─────────────────────────────────────────────────────────────────────────────
// Session persistence (Part 3, phase 11). A CLI-local Codable mirror of a chat —
// ChatMessage isn't Codable, so we use our own DTOs. Saved to <project>/.forge/
// session.json (beside the checkpoints, which the SHAs reference). SECURITY: the
// API key is NEVER persisted — it's re-resolved from config/env/--api-key on resume.
// ─────────────────────────────────────────────────────────────────────────────

struct SessionFile: Codable {
    var version = 1
    var project: String
    var framework: String
    var model: ModelRef
    var turns: [Turn]

    struct ModelRef: Codable {
        var provider: String        // "lmStudio" | "ollama" | "cloud"
        var model: String
        var baseURL: String?
    }

    struct Turn: Codable {
        var role: String            // "user" | "assistant"
        var content: String
        var checkpointSHA: String?  // pre-turn snapshot (user turns)
    }

    static func path(forProject dir: URL) -> URL {
        dir.appendingPathComponent(".forge/session.json")
    }

    static func load(projectDir: URL) -> SessionFile? {
        guard let data = try? Data(contentsOf: path(forProject: projectDir)) else { return nil }
        return try? JSONDecoder().decode(SessionFile.self, from: data)
    }

    func save(projectDir: URL) {
        let p = Self.path(forProject: projectDir)
        try? FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(self) { try? data.write(to: p, options: .atomic) }
    }

    /// Build chat history (build turns) for the agent loop.
    func chatHistory() -> [ChatMessage] {
        turns.compactMap {
            switch $0.role {
            case "user":      return ChatMessage(role: .user, content: $0.content)
            case "assistant": return ChatMessage(role: .assistant, content: $0.content)
            default:          return nil
            }
        }
    }

    /// Reconstruct a local model from the ref (LM Studio / Ollama). Cloud falls back to
    /// `fallback` (the key isn't persisted, so it's re-resolved via flags/config).
    func resolvedConfig(fallback: ModelConfig) -> ModelConfig {
        switch model.provider {
        case "lmStudio": return .lmStudio(model: model.model)
        case "ollama":   return .ollama(model: model.model)
        default:         return fallback
        }
    }

    static func providerName(for source: ModelConfig.Source) -> String {
        switch source {
        case .lmStudio: return "lmStudio"
        case .ollama:   return "ollama"
        case .cloud:    return "cloud"
        }
    }
}
