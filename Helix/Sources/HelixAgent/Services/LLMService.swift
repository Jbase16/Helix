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
        
        // Use the router to select the best model based on the prompt.
        let modelName = router.modelName(for: trimmed)
        print("[LLMService] Starting generation with model: \(modelName)")
        
        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            
            // Client-side safety: stop markers and max response size as a backstop
            let stopMarkers: [String] = ["<|end|>", "<|user|>", "<|assistant|>"]
            let maxResponseCharacters: Int = 8000 // cap to prevent runaway generations
            
            var didTerminate = false
            func emitError(_ error: HelixError) {
                if didTerminate { return }
                didTerminate = true
                onError(error)
            }
            
            defer {
                // Capture termination state before hopping to MainActor to avoid
                // mutating a captured var in a concurrently-executing context (Swift 6).
                let shouldComplete = !didTerminate
                if shouldComplete {
                    didTerminate = true
                }
                Task { @MainActor in
                    self.isGenerating = false
                    print("[LLMService] Generation finished (defer)")
                    if shouldComplete {
                        onComplete()
                    }
                }
            }
            
            guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
                print("[LLMService] Invalid URL")
                emitError(.unknown(message: "Invalid Ollama URL"))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = GenerateRequest(
                model: modelName,
                prompt: trimmed,
                system: systemPrompt,
                stream: true,
                options: GenerateOptions(stop: ["User:", "Assistant:", "<|endoftext|>"], temperature: 0.7)
            )
            
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                print("[LLMService] Encoding error: \(error)")
                emitError(.decoding(underlying: error))
                return
            }
            
            print("[LLMService] Request body encoded, calling Ollama…")
            
            // Configure a custom session with longer timeouts and connectivity waiting
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 600
            config.waitsForConnectivity = true
            let session = URLSession(configuration: config)
            
            var succeeded = false
            // Retry once on request timeout
            for attempt in 1...2 {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        // Attempt to read and log the error body
                        var errorBody = ""
                        do {
                            for try await line in bytes.lines {
                                errorBody += line + "\n"
                            }
                        } catch {
                            // ignore body read errors
                        }
                        print("[LLMService] Non-200 response: \(httpResponse.statusCode). Body: \(errorBody)")
                        let lower = errorBody.lowercased()
                        if lower.contains("not found") || lower.contains("no such model") || lower.contains("unable to load model") {
                            emitError(.modelNotAvailable(modelName))
                        } else {
                            emitError(.invalidResponse(statusCode: httpResponse.statusCode))
                        }
                        return
                    }
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            emitError(.cancellation)
                            break
                        }
                        guard let data = line.data(using: .utf8) else { continue }
                        
                        do {
                            let chunk = try JSONDecoder().decode(GenerateChunk.self, from: data)
                            
                            if let token = chunk.response, !token.isEmpty {
                                var tokenToEmit = token
                                var hitStopMarker = false
                                // If the token contains any stop marker, trim at the marker and mark to stop
                                for marker in stopMarkers {
                                    if let r = tokenToEmit.range(of: marker) {
                                        tokenToEmit = String(tokenToEmit[..<r.lowerBound])
                                        hitStopMarker = true
                                        break
                                    }
                                }

                                if !tokenToEmit.isEmpty {
                                    await MainActor.run {
                                        self.streamedResponse += tokenToEmit
                                        onToken(tokenToEmit)
                                    }
                                }

                                // Enforce a max character cap as a last resort to avoid runaways
                                let shouldStopDueToCap: Bool = await MainActor.run { self.streamedResponse.count >= maxResponseCharacters }
                                if hitStopMarker || shouldStopDueToCap {
                                    break
                                }
                            }

                            if chunk.done == true { break }
                            
                        } catch {
                            print("[LLMService] Chunk decode error: \(error)")
                            emitError(.decoding(underlying: error))
                            break
                        }
                    }
                    
                    // If we got here, streaming finished without throwing
                    succeeded = true
                    break
                    
                } catch {
                    if Task.isCancelled {
                        emitError(.cancellation)
                        return
                    }
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        print("[LLMService] Request timed out (attempt \(attempt)).")
                        if attempt < 2 {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s backoff
                            continue
                        }
                    }
                    print("[LLMService] Request failed: \(error)")
                    emitError(.network(underlying: error))
                    return
                }
            }
            
            // Fallback: if streaming did not succeed, try a non-streaming request once
            if !succeeded {
                var fallbackRequest = request
                do {
                    let fallbackBody = GenerateRequest(
                        model: modelName,
                        prompt: trimmed,
                        system: systemPrompt,
                        stream: false,
                        options: GenerateOptions(stop: ["User:", "Assistant:", "<|endoftext|>"], temperature: 0.7)
                    )
                    fallbackRequest.httpBody = try JSONEncoder().encode(fallbackBody)
                } catch {
                    print("[LLMService] Encoding error (fallback): \(error)")
                    emitError(.decoding(underlying: error))
                    return
                }
                
                do {
                    let (data, response) = try await session.data(for: fallbackRequest)
                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        let bodyString = String(data: data, encoding: .utf8) ?? ""
                        print("[LLMService] Non-200 response (fallback): \(httpResponse.statusCode). Body: \(bodyString)")
                        let lower = bodyString.lowercased()
                        if lower.contains("not found") || lower.contains("no such model") || lower.contains("unable to load model") {
                            emitError(.modelNotAvailable(modelName))
                        } else {
                            emitError(.invalidResponse(statusCode: httpResponse.statusCode))
                        }
                        return
                    }
                    do {
                        let chunk = try JSONDecoder().decode(GenerateChunk.self, from: data)
                        if let token = chunk.response, !token.isEmpty {
                            await MainActor.run {
                                self.streamedResponse += token
                                onToken(token)
                            }
                        }
                    } catch {
                        print("[LLMService] Fallback decode error: \(error)")
                        emitError(.decoding(underlying: error))
                        return
                    }
                } catch {
                    if Task.isCancelled {
                        emitError(.cancellation)
                    } else {
                        print("[LLMService] Fallback request failed: \(error)")
                        emitError(.network(underlying: error))
                    }
                    return
                }
            }
        }
    }
}

