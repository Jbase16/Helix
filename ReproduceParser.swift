
import Foundation

let text = "<tool_automated_code>auto_iam(attack=\"penetration\", target=\"https://juice-shop.herokuapp.com/#/\")</tool_automated_code>"

func testRegex(_ pattern: String, name: String) {
    do {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        print("Regex '\(name)': Found \(matches.count) matches")
        for match in matches {
            let matchString = (text as NSString).substring(with: match.range)
            print(" - Match: \(matchString)")
        }
    } catch {
        print("Regex '\(name)' Error: \(error)")
    }
}

// The current regex in ToolParser
let currentOpening = #"<tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>"#
testRegex(currentOpening, name: "Current Opening")

// A simplified proposed regex
let simpleOpening = #"<tool.*?code\s*>"#
testRegex(simpleOpening, name: "Simple Opening")

// ChatBubbleView regex
let bubbleRegex = #"<tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>run(?:_[a-z]+)*_command\(command="(.*)"\)</tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>"#
testRegex(bubbleRegex, name: "ChatBubble RunCommand")

// Generic ChatBubble
let bubbleGeneric = #"<tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>(\w+)\((.*?)\)</tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>"#
testRegex(bubbleGeneric, name: "ChatBubble Generic")
