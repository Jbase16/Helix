// WebSearchTool.swift
import Foundation

/// Tool to perform a simple web search using DuckDuckGo and return raw HTML results.
struct WebSearchTool: Tool {
    var name: String { "web_search" }
    var description: String { "Searches the web for the given query using DuckDuckGo and returns the raw HTML of the results page." }
    var usageSchema: String { "web_search(query=\"<search_query>\")" }
    var requiresPermission: Bool { false }
    var shouldCachePermission: Bool { true }

    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let query = arguments["query"]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ToolResult(output: "Error: Missing or invalid 'query' argument.", isError: true)
        }
        
        // Use curl with follow redirects (-L) and a User-Agent to avoid being blocked/redirected.
        // We also use a simple sed command to strip HTML tags for cleaner output.
        let command = "curl -s -L -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36' 'https://duckduckgo.com/html/?q=\(query)' | sed 's/<[^>]*>//g'"
        
        do {
            let result = try await RunCommandTool().run(arguments: ["command": command])
            // Further clean up whitespace
            let cleanOutput = result.output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return ToolResult(output: cleanOutput, isError: result.isError)
        } catch {
            return ToolResult(output: "Error executing web search: \(error.localizedDescription)", isError: true)
        }
    }
}
