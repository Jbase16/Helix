//
//  LLMService.swift
//  Helix
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class LLMService: ObservableObject {
    
    @Published var isGenerating: Bool = false
    @Published var streamedResponse: String = ""
    
    // You still have a router, but we won't use it until we verify UI works.
    private let router = ModelRouter()
    private var currentTask: Task<Void, Never>?
    
    // MARK: - Cancel Any In-Flight Generation
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        print("[LLMService] Generation cancelled")
    }
    
    // MARK: - Main Generate Function
    /// Generate a response for the given prompt.  Tokens are streamed back via `onToken`.  If an error occurs, `onError` is called with a `HelixError`.  Once the generation finishes or is cancelled, `onComplete` is invoked.
    func generate(prompt: String,
                  onToken: @escaping (String) -> Void,
                  onError: @escaping (HelixError) -> Void,
                  onComplete: @escaping () -> Void) {
        // Cancel any previous request
        cancel()
        
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[LLMService] Ignoring empty prompt")
            onComplete()
            return
        }
        
        streamedResponse = ""
        isGenerating = true
        
        // Use the router to select the best model based on the prompt.
        let modelName = router.modelName(for: trimmed)
        print("[LLMService] Starting generation with model: \(modelName)")
        
        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            
            defer {
                Task { @MainActor in
                    self.isGenerating = false
                    print("[LLMService] Generation finished (defer)")
                    onComplete()
                }
            }
            
            guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
                print("[LLMService] Invalid URL")
                onError(.unknown(message: "Invalid Ollama URL"))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = GenerateRequest(
                model: modelName,
                prompt: trimmed,
                stream: true
            )
            
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                print("[LLMService] Encoding error: \(error)")
                onError(.decoding(underlying: error))
                return
            }
            
            print("[LLMService] Request body encoded, calling Ollama…")
            
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    
                    print("[LLMService] Non-200 response: \(httpResponse.statusCode)")
                    onError(.invalidResponse(statusCode: httpResponse.statusCode))
                    return
                }
                
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8) else { continue }
                    
                    do {
                        let chunk = try JSONDecoder().decode(GenerateChunk.self, from: data)
                        
                        if let token = chunk.response, !token.isEmpty {
                            await MainActor.run {
                                self.streamedResponse += token
                                onToken(token)
                            }
                        }
                        
                        if chunk.done == true { break }
                        
                    } catch {
                        print("[LLMService] Chunk decode error: \(error)")
                        onError(.decoding(underlying: error))
                    }
                }
                
            } catch {
                if Task.isCancelled {
                    onError(.cancellation)
                } else {
                    print("[LLMService] Request failed: \(error)")
                    onError(.network(underlying: error))
                }
            }
        }
    }
}
