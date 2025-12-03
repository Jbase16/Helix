//
//  ClipboardTool.swift
//  Helix
//

import Foundation
import AppKit

/// Tool to read from or write to the system clipboard
struct ClipboardReadTool: Tool {
    var name: String { "clipboard_read" }
    var description: String { "Reads the current text content from the system clipboard." }
    var usageSchema: String { "clipboard_read()" }
    var requiresPermission: Bool { false }

    func run(arguments: [String : String]) async throws -> ToolResult {
        let pasteboard = NSPasteboard.general
        let content = pasteboard.string(forType: .string) ?? "(clipboard is empty)"
        return ToolResult(output: "Clipboard content:\n\(content)", isError: false)
    }
}

struct ClipboardWriteTool: Tool {
    var name: String { "clipboard_write" }
    var description: String { "Writes the specified text to the system clipboard." }
    var usageSchema: String { "clipboard_write(text=\"<content_to_copy>\")" }
    var requiresPermission: Bool { false }

    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let text = arguments["text"] else {
            return ToolResult(output: "Error: Missing required argument 'text'.", isError: true)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return ToolResult(output: "Text copied to clipboard successfully.", isError: false)
    }
}
