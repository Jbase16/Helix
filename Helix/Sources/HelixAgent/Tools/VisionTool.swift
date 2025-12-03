// VisionTool.swift
import Foundation

/// Tool to capture a screenshot of the main display and return the file path.
/// Currently it just captures the screenshot; integration with a local vision model can be added later.
struct VisionTool: Tool {
    var name: String { "vision" }
    var description: String { "Captures a screenshot of the main display and returns the absolute path to the PNG file. Useful for visual analysis. Requires user permission." }
    var usageSchema: String { "vision()" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }

    func run(arguments: [String : String]) async throws -> ToolResult {
        // Generate a temporary file path
        let timestamp = Int(Date().timeIntervalSince1970)
        let tempPath = "/tmp/vision_\(timestamp).png"
        // Use screencapture to take a screenshot without showing UI (-x)
        let command = "screencapture -x \(tempPath)"
        do {
            let result = try await RunCommandTool().run(arguments: ["command": command])
            if result.isError {
                return result
            }
            return ToolResult(output: "Screenshot saved at \(tempPath)", isError: false)
        } catch {
            return ToolResult(output: "Error capturing screenshot: \(error.localizedDescription)", isError: true)
        }
    }
}
