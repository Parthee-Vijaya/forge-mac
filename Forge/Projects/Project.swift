import Foundation

/// A Forge project: a named folder with its own generated code + chat history.
struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let folder: String
    var createdAt: Date
    var updatedAt: Date
    /// Frontend framework for this project's scaffold: "react" | "svelte" | "vue".
    var framework: String

    init(id: UUID = UUID(), name: String, folder: String, framework: String = "react",
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.folder = folder
        self.framework = framework
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Tolerant decoding: `framework` was added later, so existing projects in
    // index.json lack it — default to "react" rather than failing the whole list.
    enum CodingKeys: String, CodingKey { case id, name, folder, createdAt, updatedAt, framework }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decode(String.self, forKey: .folder)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        framework = (try? c.decode(String.self, forKey: .framework)) ?? "react"
    }
}
