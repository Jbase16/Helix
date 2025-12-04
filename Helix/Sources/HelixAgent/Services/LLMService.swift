//
//  LLMService.swift
//  Helix
//
//  Coordinator service that manages LLM interactions, including:
//  - Model routing
//  - Error recovery (retries, fallbacks)
//  - State management
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class LLMService: ObservableObject {

    @Published var isGenerating: Bool = false
    @Published var streamedResponse: String = ""
    
    private let router = ModelRouter()
    private let client = OllamaClient()
    private let streamingHandler = StreamingHandler()
    private let retryPolicy = RetryPolicy()
    
    private var currentTask: Task<Void, Never>?
    
    init() {
        // Preload the default model on init to reduce time-to-first-token
        Task {
            await preloadDefaultModel()
        }
    }
    
    /// Preload the default chat model into GPU memory for faster first response.
    func preloadDefaultModel() async {
        await client.preloadModel("dolphin-llama3")
    }
    
    // MARK: - Cancel Any In-Flight Generation
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        print("[LLMService] Generation cancelled")
    }
    
    // MARK: - Main Generate Function
    /// Generate a response for the given prompt.
    func generate(prompt: String,
                  systemPrompt: String? = nil,
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
        
        // Use the router to select the initial model
        let initialModel = router.modelName(for: trimmed)
        print("[LLMService] Starting generation with model: \(initialModel)")
        
        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            
            var currentModel = initialModel
            var attempts = 0
            let maxAttempts = 3
            var lastError: HelixError?
            
            while attempts < maxAttempts {
                do {
                    try await self.performGeneration(
                        model: currentModel,
                        prompt: trimmed,
                        systemPrompt: systemPrompt,
                        onToken: onToken
                    )
                    // If we get here, generation succeeded
                    await MainActor.run {
                        self.isGenerating = false
                        onComplete()
                    }
                    return
                } catch {
                    print("[LLMService] Generation failed with model \(currentModel): \(error)")
                    
                    // Convert to HelixError
                    let helixError: HelixError
                    if let he = error as? HelixError {
                        helixError = he
                    } else {
                        helixError = .network(underlying: error)
                    }
                    lastError = helixError
                    
                    // Check for cancellation
                    if Task.isCancelled {
                        await MainActor.run {
                            self.isGenerating = false
                            onError(.cancellation)
                        }
                        return
                    }
                    
                    // Try fallback model
                    if let fallback = self.fallbackModel(for: currentModel) {
                        print("[LLMService] Falling back from \(currentModel) to \(fallback)")
                        currentModel = fallback
                        attempts += 1
                        continue
                    }
                    
                    // No fallback available or max attempts reached
                    break
                }
            }
            
            // If we exit the loop, we failed
            let finalError = lastError
            await MainActor.run {
                self.isGenerating = false
                if let error = finalError {
                    onError(error)
                } else {
                    onError(.unknown(message: "Generation failed"))
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private nonisolated func fallbackModel(for model: String) -> String? {
        // Define fallback chain: specialized models → general → basic
        switch model {
        case "wizardlm-uncensored:13b":
            return "dolphin-llama3"
        case "deepseek-coder-v2:16b":
            return "dolphin-llama3"
        case "dolphin-llama3":
            return "llama3"  // Try standard llama3 if dolphin variant unavailable
        case "llama3":
            return "llama2"  // Last resort
        default:
            return nil
        }
    }
    
    private func performGeneration(model: String, prompt: String, systemPrompt: String?, onToken: @escaping (String) -> Void) async throws {
        
        let request = GenerateRequest(
            model: model,
            prompt: prompt,
            system: systemPrompt,
            stream: true,
            options: GenerateOptions(stop: ["User:", "Assistant:", "<|endoftext|>"], temperature: 0.7)
        )
        
        // Use RetryPolicy for network operations
        try await retryPolicy.execute {
            let (bytes, response) = try await client.streamGeneration(request: request)
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("[LLMService] Non-200 response: \(httpResponse.statusCode)")
                throw HelixError.invalidResponse(statusCode: httpResponse.statusCode)
            }
            
            // Process the stream
            let _ = try await streamingHandler.processStream(bytes: bytes) { token in
                await MainActor.run {
                    self.streamedResponse += token
                    onToken(token)
                }
            }
        }
    }
}
