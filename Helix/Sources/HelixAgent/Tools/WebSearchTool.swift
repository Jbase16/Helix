// WebSearchTool.swift
import Foundation

/// Tool to perform a simple web search using DuckDuckGo and return raw HTML results.
struct WebSearchTool: Tool {
    var name: String { "web_search" }
    var description: String { "Searches the web for the given query using DuckDuckGo and returns the raw HTML of the results page." }
    var usageSchema: String { "web_search(query=\"<search_query>\")" }
    var requiresPermission: Bool { false }

    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let query = arguments["query"]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ToolResult(output: "Error: Missing or invalid 'query' argument.", isError: true)
        }
        // Use curl to fetch DuckDuckGo HTML results.
        let command = "curl -s 'https://duckduckgo.com/html/?q=\(query)'"
        do {
            let result = try await RunCommandTool().run(arguments: ["command": command])
            return result
        } catch {
            return ToolResult(output: "Error executing web search: \(error.localizedDescription)", isError: true)
        }
    }
}
