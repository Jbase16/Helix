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
        if let attr = try? AttributedString(markdown: message.text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        } else {
            return AttributedString(message.text)
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
                Text(LocalizedStringKey(message.text))
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

