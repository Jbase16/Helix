import Foundation

/// Tool to get the current URL and page title from the active browser tab.
struct FetchBrowserContextTool: Tool {
    var name: String { "get_browser_context" }
    var description: String { "Gets the URL and title of the currently active tab in Safari or Chrome. Use this to see what page the user is looking at or referencing." }
    var usageSchema: String { "get_browser_context()" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        do {
            let (url, title) = try await BrowserService.shared.getActivePageContext()
            if url.isEmpty {
                return ToolResult(output: "No active browser tab found.", isError: false)
            }
            return ToolResult(output: "Active Tab:\nTitle: \(title)\nURL: \(url)", isError: false)
        } catch {
             return ToolResult(output: "Error getting context: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Tool to run a JavaScript snippet in the active browser tab.
struct RunBrowserJavascriptTool: Tool {
    var name: String { "run_browser_javascript" }
    var description: String { "Runs JavaScript in the active browser tab (Safari/Chrome). Returns the string result." }
    var usageSchema: String { "run_browser_javascript(script=\"<js_code>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let script = arguments["script"] else {
             return ToolResult(output: "Error: Missing 'script' argument.", isError: true)
        }
        
        do {
            let result = try await BrowserService.shared.runJavaScript(script)
            return ToolResult(output: result, isError: false)
        } catch {
             return ToolResult(output: "Error running script: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Tool to extract authentication session data (cookies/tokens) from the active tab.
struct ExtractSessionTool: Tool {
    var name: String { "extract_browser_session" }
    var description: String { "Dumps cookies and localStorage from the active browser tab. USE WITH CAUTION. Useful for session hijacking simulation or debugging auth." }
    var usageSchema: String { "extract_browser_session()" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { false } // Never cache permission for sensitive data dump
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        do {
            let json = try await BrowserService.shared.getSessionData()
            
            // Save to a file for the user instead of spewing JSON into the chat
            let success = "Session data extracted successfully."
            return ToolResult(output: "\(success)\nData: \(json.prefix(500))... (truncated)", isError: false)
        } catch {
             return ToolResult(output: "Error extracting session: \(error.localizedDescription)", isError: true)
        }
    }
}
