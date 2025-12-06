import Foundation

struct ToolCall {
    let toolName: String
    let arguments: [String: String]
}

struct ToolParser {
    static func parse(from text: String) -> ToolCall? {
        var normalizedText = text
            .replacingOccurrences(of: "<｜tool calls begin｜>", with: "")
            .replacingOccurrences(of: "<｜tool call begin｜>", with: "")
        
        print("Normalized: '\(normalizedText)'")

        if let call = parseSpecialTokens(normalizedText) {
            return call
        }
        
        // Fallback to XML
        print("Falling back to XML Check...")
        if let call = parseXMLWrapped(normalizedText) {
             print("XML Parsed!")
             return call
        }
        
        return nil
    }

    private static func parseSpecialTokens(_ text: String) -> ToolCall? {
        // Current Regex in ToolParser.swift (Step 3213)
        // Missing leading \s*
        let pattern = #"(?:function)?\s*<｜tool sep｜>\s*(\w+)([\s\S]*?)(?:<｜tool call end｜>|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) else {
            print("SpecialTokens Regex Match Failed")
            return nil 
        }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        return ToolCall(toolName: toolName, arguments: [:])
    }
    
    private static func parseXMLWrapped(_ text: String) -> ToolCall? {
        let pattern = #"<tool_code>\s*(\w+)\((.*?)\)\s*</tool_code>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) else { 
            print("XML Regex Match Failed")
            return nil 
        }
        let toolName = nsString.substring(with: match.range(at: 1))
        return ToolCall(toolName: toolName, arguments: [:])
    }
}

// User's Raw Input (Failing Case: Leading space + duplicate calls)
let input = """
 <｜tool calls begin｜><｜tool call begin｜>function<｜tool sep｜>auto_recon(target="https://juice-shop.herokuapp.com")
    The `auto_recon` tool will perform...
    <tool_code>auto_recon(target="https://juice-shop.herokuapp.com")</tool_code>
"""

if let result = ToolParser.parse(from: input) {
    print("SUCCESS: Parsed \(result.toolName)")
} else {
    print("FAILURE: Could not parse.")
}
