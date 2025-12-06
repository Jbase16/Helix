import Foundation

struct ToolCall {
    let toolName: String
    let arguments: [String: String]
}

struct ToolParser {
    static func parse(from text: String) -> ToolCall? {
        // Current Normalization in ToolParser.swift (Step 3163)
        var normalizedText = text
            .replacingOccurrences(of: "<｜tool calls begin｜>", with: "")
            .replacingOccurrences(of: "<｜tool call begin｜>", with: "")
            // .replacingOccurrences(of: "<｜tool sep｜>", with: "") // WAS REMOVED
            // .replacingOccurrences(of: "function", with: "") // WAS REMOVED
        
        print("Normalized: \n\(normalizedText)\n")

        if let call = parseSpecialTokens(normalizedText) {
            return call
        }
        return nil
    }

    private static func parseSpecialTokens(_ text: String) -> ToolCall? {
        // Current Regex in ToolParser.swift (Step 3141)
        let pattern = #"function<｜tool sep｜>\s*(\w+)([\s\S]*?)(?:<｜tool call end｜>|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { 
            print("Regex compilation failed")
            return nil 
        }
        
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) else { 
            print("Regex match failed")
            return nil 
        }
        
        let toolName = nsString.substring(with: match.range(at: 1))
        let argsBlock = nsString.substring(with: match.range(at: 2))
        
        print("Match Found: \(toolName)")
        print("Args Block: \(argsBlock)")
        
        let args = parseArguments(argsBlock)
        print("Parsed Args: \(args)")
        
        if !args.isEmpty {
            return ToolCall(toolName: toolName, arguments: args)
        }
        
        return nil
    }
    
    private static func parseArguments(_ text: String) -> [String: String] {
        var args: [String: String] = [:]
        let robustPattern = #"(\w+)\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        guard let regex = try? NSRegularExpression(pattern: robustPattern, options: [.dotMatchesLineSeparators]) else { return [:] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let key = nsString.substring(with: match.range(at: 1))
            let rawValue = nsString.substring(with: match.range(at: 2))
            args[key] = rawValue
        }
        return args
    }
}

// Full input string simulating model output with hallucinated output
let input = """
 <｜tool calls begin｜><｜tool call begin｜>function<｜tool sep｜>auto_recon
target="https://juice-shop.herokuapp.com"
json {} <｜tool call end｜><｜tool calls end｜>
<｜tool outputs begin｜><｜tool output begin｜>{"status": "success", "message": "Reconnaissance on target 'https://juice-shop.herokuapp.com' has started."}<｜tool output end｜><｜tool outputs end｜>
"""

if let result = ToolParser.parse(from: input) {
    print("SUCCESS: Parsed \(result.toolName) with args \(result.arguments)")
} else {
    print("FAILURE: Could not parse.")
}
