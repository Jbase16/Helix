import SwiftUI

// ------------------------------------------------------------
// MARK: - Chat Bubble Renderer
// ------------------------------------------------------------
// A very simple chat bubble for user vs agent messages.
//

struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var isHovering = false

    /// Attempt to convert the message text into an attributed string using Markdown formatting.
    private var attributedText: AttributedString {
        var cleanText = message.text
        
        // 1. Format `run_command` specifically to show the bash script
        // Pattern: <tool_code>run_command(command="...")</tool_code>
        // We capture the command content. Handling escaped quotes specifically.
        let runCommandPattern = #"<tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>run_command\(command="(.*)"\)</tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>"#
        
        if let regex = try? NSRegularExpression(pattern: runCommandPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsString = cleanText as NSString
            let matches = regex.matches(in: cleanText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Iterate in reverse to replace without invalidating ranges
            for match in matches.reversed() {
                let fullRange = match.range
                if match.numberOfRanges > 1 {
                    let commandRange = match.range(at: 1)
                    let commandRaw = nsString.substring(with: commandRange)
                    
                    // Unescape quotes for display
                    let commandClean = commandRaw
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                    
                    let replacement = """
                    
                    **⚡️ Executing Shell Command:**
                    ```bash
                    \(commandClean)
                    ```
                    """
                    cleanText = (cleanText as NSString).replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        // 2. Format generic tools nicely
        // Pattern: <tool_code>tool_name(...)</tool_code>
        let genericPattern = #"<tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>(\w+)\((.*?)\)</tool[_\s\-]*(?:[a-zA-Z0-9_]+[_\s\-]*)?code\s*>"#
        
        if let regex = try? NSRegularExpression(pattern: genericPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            // We use a simpler block replacement for generic tools if they weren't caught by the specific run_command one above
            // (Note: The run_command regex above replaces the tag, so this won't double-match if it worked)
            let nsString = cleanText as NSString
            let matches = regex.matches(in: cleanText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                let fullRange = match.range
                if match.numberOfRanges > 1 {
                    let toolNameRange = match.range(at: 1)
                    let toolName = nsString.substring(with: toolNameRange)
                    
                    let replacement = "\n*⚡️ Action: Calls `\(toolName)`...*"
                    cleanText = (cleanText as NSString).replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        if let attr = try? AttributedString(markdown: cleanText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        } else {
            return AttributedString(cleanText)
        }
    }

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .assistant {
                // Avatar for Assistant
                Image(systemName: "cpu")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)
                    .padding(.bottom, 4)
            } else {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Render the message body with Markdown support and text selection
                // Render the message body with Markdown support and text selection
                Text(attributedText)
                    .font(.body)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text(timestamp)
                        .font(.caption2)
                        .foregroundColor(message.role == .user ? .white.opacity(0.7) : .secondary)
                    
                    Spacer()
                    
                    // Copy Button (visible on hover)
                    if isHovering {
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(message.text, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(message.role == .user ? .white.opacity(0.8) : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }
            }
            .padding(12)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .onHover { hover in
                isHovering = hover
            }
            
            if message.role == .user {
                // Avatar for User
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 4)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 4)
    }

    /// Determine the bubble color based on the sender role.
    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(NSColor.controlBackgroundColor)
        case .system:
            return Color.orange.opacity(0.1)
        }
    }
}

