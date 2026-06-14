import Foundation

/// A Forge project: a named folder with its own generated code + chat history.
struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let folder: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, folder: String,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.folder = folder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
