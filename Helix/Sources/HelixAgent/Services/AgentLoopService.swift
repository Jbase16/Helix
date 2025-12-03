//
//  AgentLoopService.swift
//  Helix
//
//  Created by Helix Agent.
//

import Foundation

@MainActor
final class AgentLoopService {
    
    private let llm: LLMService
    private let tools: [Tool]
    
    // Maximum number of turns in a single loop to prevent infinite loops.
    private let maxTurns = 10
    
    // Cache for granted permissions (tool names)
    private var permissionCache: Set<String> = []
    
    init(llm: LLMService) {
        self.llm = llm
        self.tools = [
            ReadFileTool(),
            ListDirTool(),
            RunCommandTool(),
            WriteFileTool(),
            WebSearchTool(),
            FetchURLTool(),
            VisionTool(),
            ClipboardReadTool(),
            ClipboardWriteTool()
        ]
    }
    
    /// Runs the agent loop for a given conversation history.
    /// - Parameters:
    ///   - history: The full list of messages in the thread (including the latest user message).
    ///   - onToken: Callback for streaming tokens to the UI.
    ///   - onComplete: Callback when the entire loop is finished.
    func run(history: [ChatMessage],
             onToken: @escaping (String) -> Void,
             onRequestPermission: @escaping (ToolCall) async -> Bool,
             onError: @escaping (HelixError) -> Void,
             onComplete: @escaping () -> Void) {
        
        Task {
            // Build initial conversation history from the thread
            var conversationHistory = ""
            for msg in history {
                let role = msg.role == .user ? "User" : "Assistant"
                conversationHistory += "\(role): \(msg.text)\n"
            }
            
            var turnCount = 0
            
            while turnCount < maxTurns {
                turnCount += 1
                print("[AgentLoop] Turn \(turnCount)")
                
                // 1. Construct System Prompt
                let systemPrompt = constructSystemPrompt()
                
                // 2. Call LLM
                var currentResponse = ""
                
                // We wrap the callback to capture the full response for parsing
                let loopTokenCallback: (String) -> Void = { token in
                    currentResponse += token
                    onToken(token) // Stream to UI
                }
                
                do {
                    try await callLLM(prompt: conversationHistory, systemPrompt: systemPrompt, onToken: loopTokenCallback)
                } catch let error as HelixError {
                    onError(error)
                    onComplete()
                    return
                } catch {
                    onError(.unknown(message: error.localizedDescription))
                    onComplete()
                    return
                }
                
                // 3. Parse for Tool Calls
                conversationHistory += "\nAssistant: \(currentResponse)\n"
                
                if let toolCall = parseToolCall(from: currentResponse) {
                    print("[AgentLoop] Tool Call Detected: \(toolCall.toolName)")
                    
                    // 4. Execute Tool (with permission check)
                    let result = await executeTool(toolCall, onRequestPermission: onRequestPermission)
                    
                    // 5. Feed back to history
                    let observation = "\nObservation:\n\(result.output)\n"
                    conversationHistory += observation
                    
                    // DO NOT stream observation to UI. Let the LLM summarize it.
                    // onToken(observation) 
                    
                    // Loop continues to let LLM react to observation
                } else {
                    // No tool call - this is a direct answer, we're done
                    print("[AgentLoop] Direct answer provided, finishing.")
                    break
                }
            }
            
            onComplete()
        }
    }
    
    private func callLLM(prompt: String, systemPrompt: String, onToken: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var didResume = false

            func resumeSuccess() {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: ())
            }

            func resumeFailure(_ error: HelixError) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: error)
            }

            llm.generate(prompt: prompt, systemPrompt: systemPrompt, onToken: onToken, onError: { error in
                resumeFailure(error)
            }, onComplete: {
                resumeSuccess()
            })
        }
    }
    
    private func executeTool(_ call: ToolCall, onRequestPermission: @escaping (ToolCall) async -> Bool) async -> ToolResult {
        guard let tool = tools.first(where: { $0.name == call.toolName }) else {
            return ToolResult(output: "Error: Tool '\(call.toolName)' not found.", isError: true)
        }
        
        // Permission Check
        // Permission Check
        if tool.requiresPermission {
            // Check cache first
            if tool.shouldCachePermission && permissionCache.contains(tool.name) {
                print("[AgentLoop] Permission cached for \(tool.name)")
            } else {
                let approved = await onRequestPermission(call)
                if !approved {
                    return ToolResult(output: "User rejected the action.", isError: true)
                }
                // Cache if allowed
                if tool.shouldCachePermission {
                    permissionCache.insert(tool.name)
                }
            }
        }
        
        do {
            return try await tool.run(arguments: call.arguments)
        } catch {
            return ToolResult(output: "Error executing tool: \(error.localizedDescription)", isError: true)
        }
    }
    
    private func constructSystemPrompt() -> String {
        var schema = ""
        for tool in tools {
            schema += "\(tool.name)(\(tool.usageSchema.replacingOccurrences(of: tool.name, with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")))\n"
        }
        
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "Unknown"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "Unknown"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        return """
        You are Helix, an autonomous AI agent.
        
        CRITICAL: You are an AGENT, not a TUTOR.
        - NEVER explain how to use tools.
        - NEVER show the <tool_code> syntax to the user.
        - If the user asks for an example, JUST RUN IT.
        - If the user implies an action (e.g. "show me", "search for"), EXECUTE THE TOOL immediately.
        
        SYSTEM PATHS (Use these exact paths):
        - Home: \(home)
        - Desktop: \(desktop)
        - Documents: \(documents)
        
        CURRENT CONTEXT:
        - User: \(NSUserName())
        - Host: \(Host.current().localizedName ?? "Mac")
        
        IMPORTANT:
        - NEVER use placeholders like /Users/USER or /MacintoshHD.
        - ALWAYS use the explicit paths provided above.
        
        ---
        
        TOOLS (use ONLY when you need to actually DO something):
        
        \(schema)
        
        Tool format: <tool_code>tool_name(arg="value")</tool_code>
        
        Use tools ONLY for:
        - Reading/writing files
        - Running commands
        - Searching the web
        - Taking screenshots
        - Clipboard operations
        
        DO NOT use tools for:
        - Answering questions
        - Telling jokes
        - Explaining concepts
        - Having conversations
        
        IMPORTANT:
        - When a tool returns data (like a web search), DO NOT output the raw data.
        - ALWAYS summarize the findings in your own words.
        """
    }
    
    private func parseToolCall(from response: String) -> ToolCall? {
        // 1. Try strict XML format first: <tool_code>tool(args)</tool_code>
        let xmlPattern = #"<tool_code>\s*(\w+)\((.*?)\)\s*</tool_code>"#
        if let call = extractToolCall(from: response, pattern: xmlPattern) {
            return call
        }
        
        // 2. Fallback: Look for known tool calls at the start of a line or standalone
        // This catches cases where the model forgets the tags but writes the correct syntax.
        // We only match if the tool name is one of our actual tools to avoid false positives.
        let toolNames = tools.map { $0.name }.joined(separator: "|")
        let fallbackPattern = #"(?m)^\s*(\#(toolNames))\((.*?)\)\s*$"#
        
        if let call = extractToolCall(from: response, pattern: fallbackPattern) {
            print("[AgentLoop] Detected tool call without tags: \(call.toolName)")
            return call
        }
        
        // 3. Fallback: XML self-closing tag <tool arg="val" />
        // This catches the format <write_file path="..." content="..." />
        let selfClosingPattern = #"<(\w+)\s+(.*?)/>"#
        if let call = extractToolCall(from: response, pattern: selfClosingPattern) {
            print("[AgentLoop] Detected self-closing tool call: \(call.toolName)")
            return call
        }
        
        return nil
    }
    
    private func extractToolCall(from text: String, pattern: String) -> ToolCall? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.last else { return nil }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        let argsString = nsString.substring(with: match.range(at: 2))
        
        var arguments: [String: String] = [:]
        
        // Parse arguments: key="value"
        // We use a slightly more robust regex that handles escaped quotes if needed
        let argPattern = #"(\w+)="(.*?)""#
        guard let argRegex = try? NSRegularExpression(pattern: argPattern, options: []) else { return nil }
        
        let argMatches = argRegex.matches(in: argsString, options: [], range: NSRange(location: 0, length: (argsString as NSString).length))
        
        for argMatch in argMatches {
            let key = (argsString as NSString).substring(with: argMatch.range(at: 1))
            let value = (argsString as NSString).substring(with: argMatch.range(at: 2))
            arguments[key] = value
        }
        
        return ToolCall(toolName: toolName, arguments: arguments)
    }
}

