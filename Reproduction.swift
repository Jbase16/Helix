import Foundation

struct ToolCall {
    let toolName: String
    let arguments: [String: String]
}

struct ToolParser {
    static func parse(from text: String, knownTools: [String]) -> ToolCall? {
        // Mocking the Fuzzy Logic only
        return parseFuzzy(text, knownTools: knownTools)
    }

    private static func parseFuzzy(_ text: String, knownTools: [String]) -> ToolCall? {
        let nsString = text as NSString
        var allMatches: [(range: NSRange, call: ToolCall)] = []
        
        for tool in knownTools {
            let pattern = "(\(tool))\\s*\\(([\\s\\S]*?)\\)"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    let toolName = nsString.substring(with: match.range(at: 1))
                    let argsBlock = nsString.substring(with: match.range(at: 2))
                    
                    var candidateCall: ToolCall? = nil
                    
                    if argsBlock.contains("=") && argsBlock.contains("\"") {
                        let args = parseArguments(argsBlock)
                        if !args.isEmpty {
                            candidateCall = ToolCall(toolName: toolName, arguments: args)
                        }
                    } else if argsBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         candidateCall = ToolCall(toolName: toolName, arguments: [:])
                    }
                    
                    if let c = candidateCall {
                        allMatches.append((range: match.range, call: c))
                    }
                }
            }
        }
        
        allMatches.sort { $0.range.location < $1.range.location }
        
        if let first = allMatches.first {
            print("[MockParser] Fuzzy match selected: \(first.call.toolName) at index \(first.range.location)")
            return first.call
        }
        return nil
    }
    
    private static func parseArguments(_ text: String) -> [String: String] {
        // Simple mock parser
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

// User's Failing Case: auto_recon followed by hallucinated run_command
let input = """
Okay, I will start.

auto_recon(target="https://juice-shop.herokuapp.com")

For example, I could also use run_command(command="ls") but I won't.
"""

// Order mimics AgentLoopService: RunCommand is EARLY, AutoRecon is LATE
let knownTools = ["run_command", "auto_recon", "read_file"]

if let result = ToolParser.parse(from: input, knownTools: knownTools) {
    print("SUCCESS: Parsed \(result.toolName). Expected: auto_recon")
} else {
    print("FAILURE: Could not parse.")
}
