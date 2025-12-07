//
//  Tool.swift
//  Helix
//
//  Created by Helix Agent.
//

import Foundation

/// Represents a result from a tool execution.
struct ToolResult: Codable, Sendable {
    let output: String
    let isError: Bool
}

/// Represents a call to a tool from the LLM.
struct ToolCall: Codable, Sendable {
    let toolName: String
    let arguments: [String: String]
}

/// Protocol that all tools must conform to.
protocol Tool: Sendable {
    /// The unique name of the tool (e.g., "read_file").
    var name: String { get }
    
    /// A description of what the tool does, for the system prompt.
    var description: String { get }
    
    /// The XML schema or usage example for the tool.
    var usageSchema: String { get }
    
    /// Whether this tool requires user permission to run.
    var requiresPermission: Bool { get }
    
    /// Whether the permission for this tool should be cached for the session.
    var shouldCachePermission: Bool { get }
    
    /// Execute the tool with the given arguments.
    func run(arguments: [String: String]) async throws -> ToolResult
}

// Optional status-aware execution: default implementation calls the base run.
extension Tool {
    func run(arguments: [String: String], onStatus: ((String) -> Void)?) async throws -> ToolResult {
        return try await run(arguments: arguments)
    }
}

extension Tool {
    var shouldCachePermission: Bool { false }
}
