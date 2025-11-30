//
//  GenerateModels.swift
//  HelixAgent
//

import Foundation

struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
    let options: GenerateOptions?
}

struct GenerateOptions: Encodable {
    let stop: [String]?
    let temperature: Double?
}

struct GenerateChunk: Decodable {
    let response: String?
    let done: Bool?
}
