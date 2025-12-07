import Foundation

/// Tool allowing the agent to store and retrieve long‑term memory entries.
/// Supports two actions: 'remember' and 'recall'.  The 'remember' action
/// expects at least 'bucket' and 'content' arguments.  The 'recall' action
/// expects a 'bucket' and optional 'limit'.
struct MemoryTool: Tool {
    var name: String { "memory" }
    var description: String {
        """
        Read and write long-term memory entries. Supports actions: remember, recall.
        """
    }
    var usageSchema: String {
        """
        memory(action=\"remember\", bucket=\"user_prefs\", content=\"...\", tags=\"tag1,tag2\")
        memory(action=\"recall\", bucket=\"user_prefs\", limit=\"5\")
        """
    }
    var requiresPermission: Bool { false }
    var shouldCachePermission: Bool { true }

    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let action = arguments["action"] else {
            return ToolResult(output: "Error: missing 'action' argument.", isError: true)
        }
        switch action {
        case "remember":
            return await handleRemember(arguments: arguments)
        case "recall":
            return await handleRecall(arguments: arguments)
        default:
            return ToolResult(output: "Error: unsupported action '\(action)'", isError: true)
        }
    }

    private func handleRemember(arguments: [String : String]) async -> ToolResult {
        guard let bucket = arguments["bucket"], let content = arguments["content"] else {
            return ToolResult(output: "Error: 'bucket' and 'content' required for remember.", isError: true)
        }
        let tagsString = arguments["tags"] ?? ""
        let tags = tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Perform the write on the main actor to respect HelixMemoryStore's isolation
        await MainActor.run {
            HelixMemoryStore.shared.remember(content, in: bucket, tags: tags)
        }
        return ToolResult(output: "Memory stored in bucket '\(bucket)'.", isError: false)
    }

    private func handleRecall(arguments: [String : String]) async -> ToolResult {
        guard let bucket = arguments["bucket"] else {
            return ToolResult(output: "Error: 'bucket' required for recall.", isError: true)
        }
        let limit = Int(arguments["limit"] ?? "10") ?? 10
        // Read from the main actor to respect HelixMemoryStore's isolation
        let entries: [HelixMemoryEntry] = await MainActor.run {
            HelixMemoryStore.shared.recall(bucket: bucket, limit: limit)
        }
        do {
            let data = try JSONEncoder().encode(entries)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            return ToolResult(output: json, isError: false)
        } catch {
            return ToolResult(output: "Error encoding recall results: \(error)", isError: true)
        }
    }
}
