// WriteFileTool.swift
import Foundation

/// Tool to write content to a file. Overwrites the file if it exists.
struct WriteFileTool: Tool {
    var name: String { "write_file" }
    var description: String { "Writes the provided content to the specified absolute file path. Overwrites existing file. Use with caution." }
    var usageSchema: String { "write_file(path=\"<absolute_path>\", content=\"<file_content>\")" }
    var requiresPermission: Bool { true }

    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let path = arguments["path"], let content = arguments["content"] else {
            return ToolResult(output: "Error: Missing required arguments 'path' or 'content'.", isError: true)
        }
        let url = URL(fileURLWithPath: path)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolResult(output: "Successfully wrote to \(path).", isError: false)
        } catch {
            return ToolResult(output: "Error writing file: \(error.localizedDescription)", isError: true)
        }
    }
}
