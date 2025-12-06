//
//  ToolParser.swift
//  Helix
//
//  Robust parser for tool calls, handling various formats and edge cases.
//

import Foundation

struct ToolParser {
    
    /// Tries to parse a tool call from the model response.
    /// Supports:
    /// 1. XML-wrapped: <tool_code>name(arg="val")</tool_code>
    /// 2. Function-style: name(arg="val") (at start of line)
    /// 3. XML self-closing: <name arg="val" />
    /// 4. Malformed: <tool_code>name</tool_code>\narg="val"
    static func parse(from text: String, knownTools: [String]) -> ToolCall? {
        // Normalize all variants of tool_code tags using regex
        var normalizedText = text
        
        // Match any variation of <tool_code>, <tool_automated_important_code>, <tool code>, etc.
        // Extremely permissive: <tool...code>
        if let openingRegex = try? NSRegularExpression(pattern: #"<tool.*?code\s*>"#, options: [.caseInsensitive]) {
            normalizedText = openingRegex.stringByReplacingMatches(
                in: normalizedText,
                options: [],
                range: NSRange(normalizedText.startIndex..., in: normalizedText),
                withTemplate: "<tool_code>"
            )
        }
        
        // Closing tag: generic matching </tool...code> - extremely permissive
        if let closingRegex = try? NSRegularExpression(pattern: #"</tool.*?code\s*>"#, options: [.caseInsensitive]) {
            normalizedText = closingRegex.stringByReplacingMatches(
                in: normalizedText,
                options: [],
                range: NSRange(normalizedText.startIndex..., in: normalizedText),
                withTemplate: "</tool_code>"
            )
        }
        
        // 1. Try strict XML format first (most reliable)
        if let call = parseXMLWrapped(normalizedText) {
            return call
        }
        
        // 2. Try malformed format: <tool_code>name</tool_code> followed by args
        if let call = parseMalformedXML(normalizedText) {
            return call
        }
        
        // 3. Try self-closing XML tag
        if let call = parseSelfClosingXML(normalizedText) {
            return call
        }
        
        // 4. Fallback: Function style
        if let call = parseFunctionStyle(normalizedText, knownTools: knownTools) {
            return call
        }
        
        return nil
    }
    
    // MARK: - Private Parsers
    
    private static func parseXMLWrapped(_ text: String) -> ToolCall? {
        // Pattern: <tool_code>name(args)</tool_code>
        // Note: Chinese variants are normalized to English before reaching here
        let pattern = #"<tool_code>\s*(\w+)\((.*?)\)\s*</tool_code>"#
        return extractCall(from: text, pattern: pattern)
    }
    
    /// Parses malformed format where model puts tool name in tags but args outside:
    /// <tool_code>run_command</tool_code>
    /// command="open /Applications"
    private static func parseMalformedXML(_ text: String) -> ToolCall? {
        // Pattern: <tool_code>name</tool_code> followed by args on next line(s)
        let pattern = #"<tool_code>\s*(\w+)\s*</tool_code>\s*\n?(.*?)(?:\n\n|$)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.last else { return nil }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        let argsString = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only proceed if there are actual arguments (key="value" pattern)
        guard argsString.contains("=") && argsString.contains("\"") else { return nil }
        
        let args = parseArguments(argsString)
        
        // Must have at least one parsed argument to be valid
        guard !args.isEmpty else { return nil }
        
        print("[ToolParser] Parsed malformed format: \(toolName) with args: \(args)")
        return ToolCall(toolName: toolName, arguments: args)
    }
    
    private static func parseFunctionStyle(_ text: String, knownTools: [String]) -> ToolCall? {
        // Pattern: ^name(args)$
        // We only match if the name is a known tool to avoid false positives
        let toolsPattern = knownTools.joined(separator: "|")
        let pattern = #"(?m)^\s*(\#(toolsPattern))\(([\s\S]*?)\)\s*$"#
        return extractCall(from: text, pattern: pattern)
    }
    
    private static func parseSelfClosingXML(_ text: String) -> ToolCall? {
        // Pattern: <name arg="val" ... />
        let pattern = #"<(\w+)\s+([^>]*?)/>"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.last else { return nil }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        let argsString = nsString.substring(with: match.range(at: 2))
        
        // Parse attributes: key="value"
        let args = parseAttributes(argsString)
        return ToolCall(toolName: toolName, arguments: args)
    }
    
    private static func extractCall(from text: String, pattern: String) -> ToolCall? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.last else { return nil }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        let argsContent = nsString.substring(with: match.range(at: 2))
        
        let args = parseArguments(argsContent)
        return ToolCall(toolName: toolName, arguments: args)
    }
    
    // MARK: - Argument Parsing
    
    /// Parses `key="value", key2="value2"` string into a dictionary.
    /// Handles escaped quotes and newlines.
    private static func parseArguments(_ text: String) -> [String: String] {
        var args: [String: String] = [:]
        
        // We use a scanner-like approach or a robust regex
        // Regex for key="value" where value can contain escaped quotes
        // let pattern = #"(\w+)\s*=\s*"(.*?)""#
        
        // We need to handle the fact that .*? is non-greedy but might stop early on an escaped quote.
        // A better regex for a quoted string is: "([^"\\]*(\\.[^"\\]*)*)"
        
        let robustPattern = #"(\w+)\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        
        guard let regex = try? NSRegularExpression(pattern: robustPattern, options: [.dotMatchesLineSeparators]) else { return [:] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let key = nsString.substring(with: match.range(at: 1))
            let rawValue = nsString.substring(with: match.range(at: 2))
            
            // Unescape the value
            let unescaped = rawValue
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
            
            args[key] = unescaped
        }
        
        return args
    }
    
    /// Parses XML attributes `key="value"`
    private static func parseAttributes(_ text: String) -> [String: String] {
        // Same logic as parseArguments
        return parseArguments(text)
    }
}
