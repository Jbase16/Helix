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
    func generate(prompt: String, onToken: @escaping (String) -> Void) {
        // Cancel any previous request
        cancel()

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[LLMService] Ignoring empty prompt")
            return
        }

        streamedResponse = ""
        isGenerating = true

        // 🔴 TEMPORARY: Hardwire to a known-good model.
        // let modelName = router.modelName(for: trimmed)
        let modelName = "llama3:latest"
        print("[LLMService] Starting generation with model: \(modelName)")

        currentTask = Task.detached { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.isGenerating = false
                    print("[LLMService] Generation finished (defer)")
                }
            }

            guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
                print("[LLMService] Invalid URL")
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
                return
            }

            print("[LLMService] Request body encoded, calling Ollama…")

            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: request)

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        print("[LLMService] Task cancelled mid-stream")
                        break
                    }

                    guard !line.isEmpty else { continue }
                    guard let data = line.data(using: .utf8) else { continue }

                    do {
                        let chunk = try JSONDecoder().decode(GenerateChunk.self, from: data)

                        if let token = chunk.response, !token.isEmpty {
                            await MainActor.run {
                                self.streamedResponse += token
                                onToken(token)
                            }
                        }

                        if chunk.done == true {
                            print("[LLMService] Chunk signaled done")
                            break
                        }

                    } catch {
                        print("[LLMService] Chunk decode error: \(error)")
                        continue
                    }
                }

            } catch {
                if Task.isCancelled {
                    print("[LLMService] Request cancelled (outer catch)")
                } else {
                    print("[LLMService] Request failed: \(error)")
                }
            }
        }
    }
}
