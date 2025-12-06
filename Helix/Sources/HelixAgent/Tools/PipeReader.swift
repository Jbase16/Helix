import Foundation

// Helper for thread-safe data accumulation
final class PipeReader: @unchecked Sendable {
    private nonisolated(unsafe) var data = Data()
    private let queue = DispatchQueue(label: "com.helix.pipereader")
    
    nonisolated init() {}
    
    nonisolated func append(_ chunk: Data) {
        queue.async { [weak self] in
            // Because we are in a nonisolated method, capturing `self` is tricky if `self` is actor-isolated.
            // But PipeReader is a class, not an actor.
            // The issue before was `data` property was inferred as MainActor.
            // By being in a new file, it should be neutral.
            self?.data.append(chunk)
        }
    }
    
    nonisolated func read() -> Data {
        queue.sync { return data }
    }
}
