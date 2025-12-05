import Foundation

/// Tool that returns important filesystem and configuration paths.  This allows
/// the agent to discover where to read and write files without guessing.
struct GetPathsTool: Tool {
    var name: String { "get_paths" }

    var description: String {
        "Returns important filesystem paths and Helix config directories so you can use correct paths without guessing."
    }

    var usageSchema: String {
        """
        get_paths()
        """
    }

    /// This tool does not require explicit permission; it is read‑only.
    var requiresPermission: Bool { false }
    var shouldCachePermission: Bool { true }

    func run(arguments: [String : String]) async throws -> ToolResult {
        // Compute OS paths
        let fm = FileManager.default
        let homeURL = fm.homeDirectoryForCurrentUser
        let home = homeURL.path
        func dir(_ type: FileManager.SearchPathDirectory, fallback: String) -> String {
            fm.urls(for: type, in: .userDomainMask).first?.path ?? fallback
        }
        let desktop   = dir(.desktopDirectory,   fallback: home + "/Desktop")
        let documents = dir(.documentDirectory,  fallback: home + "/Documents")
        let downloads = dir(.downloadsDirectory, fallback: home + "/Downloads")

        // Load current config
        let config = HelixConfigStore.shared.config

        struct Payload: Codable {
            let home: String
            let desktop: String
            let documents: String
            let downloads: String
            let projectDirectories: [String]
            let modelDirectory: String
            let tempDirectory: String
            let customPaths: [String: String]
        }
        let payload = Payload(
            home: home,
            desktop: desktop,
            documents: documents,
            downloads: downloads,
            projectDirectories: config.projectDirectories,
            modelDirectory: config.modelDirectory,
            tempDirectory: config.tempDirectory,
            customPaths: config.customPaths
        )

        do {
            let data = try JSONEncoder().encode(payload)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(output: json, isError: false)
        } catch {
            return ToolResult(output: "Error encoding paths payload: \(error.localizedDescription)", isError: true)
        }
    }
}
