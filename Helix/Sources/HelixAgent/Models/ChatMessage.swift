//
//  ChatMessage.swift
//  HelixAgent
//
//
//  Represents a single message inside a chat thread.
//  (Updated for sync)
//

import Foundation

struct ChatMessage: Identifiable, Codable, Hashable {

    enum Role: String, Codable, Hashable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var text: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}
