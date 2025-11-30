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
    
    /// Execute the tool with the given arguments.
    func run(arguments: [String: String]) async throws -> ToolResult
}
