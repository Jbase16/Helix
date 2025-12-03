// FetchURLTool.swift
import Foundation

/// Tool to fetch the raw content of a URL (HTML, JSON, etc.) and return it as a string.
struct FetchURLTool: Tool {
    var name: String { "fetch_url" }
    var description: String { "Fetches the content at the given absolute URL and returns the response body as a string. Useful for retrieving API responses or web pages." }
    var usageSchema: String { "fetch_url(url=\"<absolute_url>\")" }
    var requiresPermission: Bool { false }
    var shouldCachePermission: Bool { true }

    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let urlString = arguments["url"], let url = URL(string: urlString) else {
            return ToolResult(output: "Error: Missing or invalid 'url' argument.", isError: true)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                return ToolResult(output: content, isError: false)
            } else {
                return ToolResult(output: "Error: Unable to decode response as UTF-8 string.", isError: true)
            }
        } catch {
            return ToolResult(output: "Error fetching URL: \(error.localizedDescription)", isError: true)
        }
    }
}
