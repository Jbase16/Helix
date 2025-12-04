//
//  StreamingHandler.swift
//  Helix
//
//  Handles parsing of streaming responses from Ollama.
//

import Foundation

actor StreamingHandler {
    private let stopMarkers: [String] = ["<|end|>", "<|user|>", "<|assistant|>"]
    private let maxResponseCharacters: Int = 8000
    
    func processStream(bytes: URLSession.AsyncBytes, onToken: @escaping (String) async -> Void) async throws -> String {
        var fullResponse = ""
        
        for try await line in bytes.lines {
            if Task.isCancelled { throw HelixError.cancellation }
            guard let data = line.data(using: .utf8) else { continue }
            
            let chunk = try JSONDecoder().decode(GenerateChunk.self, from: data)
            
            if let token = chunk.response, !token.isEmpty {
                var tokenToEmit = token
                var hitStopMarker = false
                
                // Check for stop markers
                for marker in stopMarkers {
                    if let r = tokenToEmit.range(of: marker) {
                        tokenToEmit = String(tokenToEmit[..<r.lowerBound])
                        hitStopMarker = true
                        break
                    }
                }
                
                if !tokenToEmit.isEmpty {
                    fullResponse += tokenToEmit
                    await onToken(tokenToEmit)
                }
                
                // Check limits
                if fullResponse.count >= maxResponseCharacters {
                    break
                }
                
                if hitStopMarker {
                    break
                }
            }
            
            if chunk.done == true { break }
        }
        
        return fullResponse
    }
}
