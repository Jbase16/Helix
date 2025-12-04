//
//  OllamaClient.swift
//  Helix
//
//  Handles low-level networking with the Ollama API.
//

import Foundation

// MARK: - Request Models

struct GenerateRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
    let options: GenerateOptions?
    
    enum CodingKeys: String, CodingKey {
        case model, prompt, system, stream, options
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(system, forKey: .system)
        try container.encode(stream, forKey: .stream)
        try container.encode(options, forKey: .options)
    }
}

struct GenerateOptions: Encodable, Sendable {
    let stop: [String]?
    let temperature: Double?
    
    enum CodingKeys: String, CodingKey {
        case stop, temperature
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stop, forKey: .stop)
        try container.encode(temperature, forKey: .temperature)
    }
}

struct GenerateChunk: Decodable, Sendable {
    let response: String?
    let done: Bool?
    
    enum CodingKeys: String, CodingKey {
        case response, done
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.response = try container.decodeIfPresent(String.self, forKey: .response)
        self.done = try container.decodeIfPresent(Bool.self, forKey: .done)
    }
}

// MARK: - Client

actor OllamaClient {
    private let baseURL = URL(string: "http://127.0.0.1:11434/api/generate")!
    
    func streamGeneration(request: GenerateRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        
        return try await session.bytes(for: urlRequest)
    }
    
    func generate(request: GenerateRequest) async throws -> (Data, URLResponse) {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)
        
        return try await session.data(for: urlRequest)
    }
    
    nonisolated func decodeChunk(_ data: Data) throws -> GenerateChunk {
        return try JSONDecoder().decode(GenerateChunk.self, from: data)
    }
}
