import Foundation
import Combine

/// Singleton store that publishes the current HelixConfig and persists changes.
/// Any part of the app can observe this store to react to configuration updates
/// at runtime.  Changes are debounced to avoid excessive disk writes.
@MainActor
final class HelixConfigStore: ObservableObject {
    /// The shared instance for the entire application.
    static let shared = HelixConfigStore()

    /// The current configuration.  Updating this value will automatically
    /// persist it to disk after a short debounce interval.
    @Published var config: HelixConfig

    private var saveCancellable: AnyCancellable?

    private init() {
        self.config = HelixConfig.load()
        // Debounce saves so we don't write to disk on every keystroke.
        saveCancellable = $config
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { newConfig in
                try? HelixConfig.save(newConfig)
            }
    }

    /// Reload the configuration from disk, overwriting any unsaved changes.
    func reload() {
        self.config = HelixConfig.load()
    }
}
