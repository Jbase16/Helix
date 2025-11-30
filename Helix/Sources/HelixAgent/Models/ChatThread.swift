//
//  ChatThread.swift
//  Helix
//
//  Represents a single conversation thread containing many chat messages.
//

import Foundation

struct ChatThread: Identifiable, Codable, Hashable {

    /// Unique thread ID.
    let id: UUID

    /// Human-friendly title shown in the UI (“Main Chat”, “LLM Debug”, etc.)
    var title: String

    /// The messages that belong to this thread.
    var messages: [ChatMessage]

    /// Timestamp of last activity — useful for sorting in UI.
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.lastUpdated = Date()
    }

    /// Adds a message to the thread and updates lastUpdated.
    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        lastUpdated = Date()
    }

    /// Removes all messages while keeping the thread itself.
    mutating func clear() {
        messages.removeAll()
        lastUpdated = Date()
    }

    /// Convenience accessor for the thread’s last message text.
    var lastMessageText: String? {
        messages.last?.text
    }

    /// Merges another message array into this thread.
    mutating func merge(_ newMessages: [ChatMessage]) {
        messages.append(contentsOf: newMessages)
        lastUpdated = Date()
    }
}

