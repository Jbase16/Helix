import Foundation
import Combine

/// Persistent store for long‑term memory.  Entries are appended when the agent
/// is asked to remember things and recalled on demand.  Changes are debounced
/// and written to disk automatically.
@MainActor
final class HelixMemoryStore: ObservableObject {
    static let shared = HelixMemoryStore()

    @Published private(set) var entries: [HelixMemoryEntry] = []

    private let fileURL: URL
    private var saveCancellable: AnyCancellable?

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Helix", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("memory.json")

        self.entries = Self.load(from: fileURL)

        // Debounce saves to avoid constant writes
        saveCancellable = $entries
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] newEntries in
                guard let self else { return }
                Self.save(newEntries, to: self.fileURL)
            }
    }

    private static func load(from url: URL) -> [HelixMemoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([HelixMemoryEntry].self, from: data)
        } catch {
            return []
        }
    }

    private static func save(_ entries: [HelixMemoryEntry], to url: URL) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url)
        } catch {
            // Errors are ignored for now; could log if needed.
        }
    }

    // MARK: - Public API
    /// Add a memory to the store.
    func remember(_ content: String, in bucket: String, tags: [String] = []) {
        let entry = HelixMemoryEntry(bucket: bucket, content: content, tags: tags)
        entries.append(entry)
    }

    /// Remove a memory by id.
    func forget(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Recall the most recent entries in a bucket.
    func recall(bucket: String, limit: Int = 20) -> [HelixMemoryEntry] {
        return entries
            .filter { $0.bucket == bucket }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }
}
