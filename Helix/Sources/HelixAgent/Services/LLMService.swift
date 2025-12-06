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

    // MARK: - Chat Function
    /// Generate a chat response for the given messages.
    func chat(messages: [ChatMessageDTO],
              systemPrompt: String? = nil,
              onToken: @escaping (String) -> Void,
              onError: @escaping (HelixError) -> Void,
              onComplete: @escaping () -> Void) {
        // Cancel any previous request
        cancel()
        
        guard !messages.isEmpty else {
            print("[LLMService] Ignoring empty chat history")
            onComplete()
            return
        }
        
        streamedResponse = ""
        isGenerating = true
        
        // Use the router to select the initial model based on the last user message
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        let initialModel = router.modelName(for: lastUserMessage)
        print("[LLMService] Starting chat with model: \(initialModel)")
        
        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            
            var currentModel = initialModel
            var attempts = 0
            let maxAttempts = 3
            var lastError: HelixError?
            
            while attempts < maxAttempts {
                do {
                    try await self.performChat(
                        model: currentModel,
                        messages: messages,
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
                    print("[LLMService] Chat failed with model \(currentModel): \(error)")
                    
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
                    onError(.unknown(message: "Chat generation failed"))
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private nonisolated func fallbackModel(for model: String) -> String? {
        // Define fallback chain: specialized models → general → basic
        switch model {
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
    
    private func performChat(model: String, messages: [ChatMessageDTO], systemPrompt: String?, onToken: @escaping (String) -> Void) async throws {
        
        // Prepend system prompt if provided
        var finalMessages = messages
        if let system = systemPrompt {
            finalMessages.insert(ChatMessageDTO(role: "system", content: system), at: 0)
        }
        
        let request = ChatRequest(
            model: model,
            messages: finalMessages,
            stream: true,
            options: GenerateOptions(stop: ["<|endoftext|>"], temperature: 0.9)
        )
        
        try await retryPolicy.execute {
            let (bytes, response) = try await client.streamChat(request: request)
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("[LLMService] Non-200 response: \(httpResponse.statusCode)")
                throw HelixError.invalidResponse(statusCode: httpResponse.statusCode)
            }
            
            // Custom stream processing for ChatChunk
            for try await line in bytes.lines {
                // print("[LLMService] Raw line: \(line)") // Uncomment for extreme verbosity
                guard let data = line.data(using: .utf8) else { continue }
                
                do {
                    let chunk = try await client.decodeChatChunk(data)
                    if let content = chunk.message?.content {
                        // print("[LLMService] Token: \(content)")
                        await MainActor.run {
                            self.streamedResponse += content
                            onToken(content)
                        }
                    }
                } catch {
                    print("[LLMService] JSON Decode Error: \(error)")
                    print("[LLMService] Failed Line: \(line)")
                    continue
                }
            }
        }
    }
}
