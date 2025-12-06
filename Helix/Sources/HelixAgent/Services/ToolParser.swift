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
            .replacingOccurrences(of: "<｜tool calls begin｜>", with: "")
            .replacingOccurrences(of: "<｜tool call begin｜>", with: "")
            // DO NOT strip <｜tool sep｜> or "function" here, as parseSpecialTokens relies on them.
        
        // Match any variation of <tool_code>, <tool_automated_important_code>, <tool code>, etc.
        
        // After stripping, we might be left with just "auto_recon(...)" which parseFunctionStyle can pick up.
        // But wait, parseFunctionStyle checks knownTools.
        
        // Let's re-add the "Permissive Check" for function style which is #5.
        // If we strip "function<sep>", we get "name(args)".
        
        // Match any variation of <tool_code>, <tool_automated_important_code>, <tool code>, etc.
        
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
        
        // Match <tool_activated> (common hallucination) -> <tool_code>
        if let activatedRegex = try? NSRegularExpression(pattern: #"<tool.*?activated\s*>"#, options: [.caseInsensitive]) {
            normalizedText = activatedRegex.stringByReplacingMatches(
                in: normalizedText,
                options: [],
                range: NSRange(normalizedText.startIndex..., in: normalizedText),
                withTemplate: "<tool_code>"
            )
        }
        
        // Closing tag: generic matching </tool...code> or </tool...activated>
        if let closingRegex = try? NSRegularExpression(pattern: #"</tool.*?(?:code|activated)\s*>"#, options: [.caseInsensitive]) {
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
        
        // 4. Try Special Tokens (DeepSeek/Qwen style)
        if let call = parseSpecialTokens(normalizedText) {
            return call
        }
        
        // 5. Fallback: Function style (Strict)
        if let call = parseFunctionStyle(normalizedText, knownTools: knownTools) {
            return call
        }
        
        // 6. FINAL FALLBACK: Fuzzy Search
        // If the text contains "function_name(arg="val")" anywhere, just grab it.
        // This is dangerous but necessary if the model's formatting is messy.
        if let call = parseFuzzy(normalizedText, knownTools: knownTools) {
            print("[ToolParser] Fuzzy match succeeded: \(call.toolName)")
            return call
        }
        
        return nil
    }
    
    // MARK: - Private Parsers
    
    private static func parseSpecialTokens(_ text: String) -> ToolCall? {
        // DeepSeek/Qwen Raw Format
        // Example: function<｜tool sep｜>auto_recon
        // ALSO support: function|auto_recon (pipe) as requested/observed by user
        
        // Pattern matches:
        // 1. Optional 'function'
        // 2. Separator: <｜tool sep｜> OR | OR ｜
        // 3. Tool Name
        let pattern = #".*?(?:<｜tool sep｜>|\||｜)(?:\s*)(\w+)([\s\S]*?)(?:<｜tool call end｜>|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        
        // Log what we are parsing to debug whitespace issues
        print("[ToolParser] Debug: Parsing normalized text of length \(text.count)")
        if text.count < 200 { print("[ToolParser] Debug: Content: '\(text)'") }
        
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) else {
            print("[ToolParser] Debug: Regex match failed in parseSpecialTokens.")
            return nil 
        }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        let argsBlock = nsString.substring(with: match.range(at: 2))
        
        // The args block might contain 'json {}' or just newlines with 'key="val"'
        // We reuse parseArguments which handles key="val"
        let args = parseArguments(argsBlock)
        
        if !args.isEmpty {
            return ToolCall(toolName: toolName, arguments: args)
        }
        
        return nil
    }
    
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
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
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
    
    private static func parseAttributes(_ text: String) -> [String: String] {
        // Same logic as parseArguments
        return parseArguments(text)
    }
    
    /// Scans the entire text for "known_tool(args)" pattern, ignoring all XML/Separator noise.
    /// This is the "Nuclear Option" for parsing.
    private static func parseFuzzy(_ text: String, knownTools: [String]) -> ToolCall? {
        // Regex: (tool_name)\((.*?)\)
        // We iterate through known tools to find matches
        
        let nsString = text as NSString
        
        for tool in knownTools {
            // Flexible pattern: toolName( [whitespace] args [whitespace] )
            let pattern = "(\(tool))\\s*\\(([\\s\\S]*?)\\)"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                
                // Grab the first valid match that has key="value" style args
                for match in matches {
                    let toolName = nsString.substring(with: match.range(at: 1))
                    let argsBlock = nsString.substring(with: match.range(at: 2))
                    
                    // Validate args look like args
                    if argsBlock.contains("=") && argsBlock.contains("\"") {
                        let args = parseArguments(argsBlock)
                        if !args.isEmpty {
                            return ToolCall(toolName: toolName, arguments: args)
                        }
                    } else if argsBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Handle no-arg tools like get_paths()
                         return ToolCall(toolName: toolName, arguments: [:])
                    }
                }
            }
        }
        
        return nil
    }
}
