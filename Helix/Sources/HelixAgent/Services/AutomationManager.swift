import Foundation
import Combine

/// Manager that reacts to configuration changes and triggers background tasks.
/// This can be expanded to perform indexing, model loading, etc. when paths
/// change.  It observes HelixConfigStore and performs actions accordingly.
@MainActor
final class AutomationManager {
    static let shared = AutomationManager()

    private var cancellables = Set<AnyCancellable>()
    private init() {
        let configStore = HelixConfigStore.shared
        configStore.$config
            // Only react when any of the top-level fields change
            .removeDuplicates(by: { lhs, rhs in
                lhs.projectDirectories == rhs.projectDirectories &&
                lhs.modelDirectory == rhs.modelDirectory &&
                lhs.tempDirectory == rhs.tempDirectory &&
                lhs.customPaths == rhs.customPaths
            })
            .sink { [weak self] newConfig in
                self?.handleConfigChange(newConfig)
            }
            .store(in: &cancellables)
    }

    private func handleConfigChange(_ config: HelixConfig) {
        // Ensure the temp directory exists on disk
        let fm = FileManager.default
        if !fm.fileExists(atPath: config.tempDirectory) {
            try? fm.createDirectory(atPath: config.tempDirectory, withIntermediateDirectories: true)
        }
        // Additional automation tasks can be added here. For example:
        // - trigger project indexing when projectDirectories change
        // - reload models when modelDirectory changes
    }
}
