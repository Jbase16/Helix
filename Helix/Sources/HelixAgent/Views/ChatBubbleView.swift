import SwiftUI

// ------------------------------------------------------------
// MARK: - Chat Bubble Renderer
// ------------------------------------------------------------
// A very simple chat bubble for user vs agent messages.
//

struct ChatBubbleView: View {
    let message: ChatMessage

    /// Attempt to convert the message text into an attributed string using Markdown formatting.  Falls back to plain text on failure.
    private var attributedText: AttributedString {
        if let attr = try? AttributedString(markdown: message.text) {
            return attr
        } else {
            return AttributedString(message.text)
        }
    }

    /// A human‑readable timestamp for the message.
    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .assistant {
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                // Render the message body with Markdown support
                Text(attributedText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                // Timestamp below the bubble
                Text(timestamp)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if message.role == .user {
                Spacer()
            }
        }
    }

    /// Determine the bubble color based on the sender role.
    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.2)
        case .assistant:
            return Color.green.opacity(0.2)
        case .system:
            return Color.orange.opacity(0.2)
        }
    }
}

