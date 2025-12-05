import Foundation

/// User-configurable settings for Helix.  This struct holds the directories and
/// paths that Helix needs in order to understand the user's environment without
/// hard‑coding any absolute paths in source code.
struct HelixConfig: Codable {
    /// Directories where the user's projects live.  The agent will treat any
    /// path in this list as a root for project searches and file operations.
    var projectDirectories: [String]
    /// Directory where large model files are stored.
    var modelDirectory: String
    /// Directory where Helix can create scratch files, caches, etc.
    var tempDirectory: String
    /// Arbitrary additional path bindings keyed by a short name.
    var customPaths: [String: String]

    /// A reasonable default configuration.  Uses the user's home directory to
    /// derive sensible defaults and includes a secondary drive on `/Volumes` if
    /// present.  If you mount your own drive named ByteMe, Helix will include
    /// it automatically.
    static var `default`: HelixConfig {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Attempt to include a ByteMe volume if it exists.
        let byteMePath = "/Volumes/ByteMe"
        let projectDirs: [String] = {
            var dirs = [home + "/Developer"]
            if fm.fileExists(atPath: byteMePath) {
                dirs.append(byteMePath + "/Developer")
            }
            return dirs
        }()

        return HelixConfig(
            projectDirectories: projectDirs,
            modelDirectory: byteMePath + "/ollama-models",
            tempDirectory: home + "/.helix-temp",
            customPaths: [:]
        )
    }

    /// Load a config from disk, falling back to defaults if it does not exist
    /// or fails to decode.  When no file exists, the default config will be
    /// persisted automatically.
    static func load() -> HelixConfig {
        let url = configFileURL()
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            // Persist the default for first use
            let def = Self.default
            try? save(def)
            return def
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(HelixConfig.self, from: data)
        } catch {
            // Fall back gracefully on any failure
            return Self.default
        }
    }

    /// Persist a config to disk.  Creates the Application Support directory as
    /// necessary.
    static func save(_ config: HelixConfig) throws {
        let url = configFileURL()
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(config)
        try data.write(to: url)
    }

    /// Construct the URL for the config file in Application Support.
    private static func configFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Helix/config.json")
    }
}
