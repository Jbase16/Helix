import Foundation

/// Represents a single entry in the long‑term memory store.  Memories are
/// grouped into buckets and may be tagged for easier recall.
struct HelixMemoryEntry: Codable, Identifiable {
    let id: UUID
    let bucket: String
    let content: String
    let createdAt: Date
    var tags: [String]

    init(bucket: String, content: String, tags: [String] = []) {
        self.id = UUID()
        self.bucket = bucket
        self.content = content
        self.createdAt = Date()
        self.tags = tags
    }
}

