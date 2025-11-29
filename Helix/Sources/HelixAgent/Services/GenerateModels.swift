//
//  GenerateModels.swift
//  Helix
//

import Foundation

nonisolated
struct GenerateRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let stream: Bool
}

nonisolated
struct GenerateChunk: Decodable, Sendable {
    let response: String?
    let done: Bool?
}
