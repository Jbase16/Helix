//
//  ModelRouter.swift
//  Helix
//

import Foundation

@MainActor
final class ModelRouter {

    // MARK: - Model Names
    // Use a smaller default model for heavy coding to avoid huge local requirements.
    private let bigCode = "deepseek-coder-v2:16b"      // smaller heavy coding & reasoning
    private let generalChat = "dolphin-llama3"      // everyday assistant
    private let turbo = "dolphin-llama3"            // hyperfast small tasks
    private let nsfw = "dolphin-mistral"      // explicit/NSFW/edgy content
    
    // MARK: - Routing Entry Point
    func modelName(for prompt: String) -> String {
        // 1. Extract the latest user message if this looks like a conversation history
        let (latestMessage, historyContext) = parsePrompt(prompt)
        let lowerPrompt = latestMessage.lowercased()
        let lowerHistory = historyContext.lowercased()

        // 2. NSFW Check (Highest Priority)
        if isNSFWRequest(prompt: lowerPrompt) {
            print("[ModelRouter] Routing → NSFW MODEL (wizardlm-uncensored)")
            return nsfw
        }

        // 3. Coding Check
        // If the current prompt is about coding OR we were just coding (stickiness)
        if isSeriousCoding(prompt: lowerPrompt) {
            print("[ModelRouter] Routing → BIG CODE MODEL (explicit request)")
            return bigCode
        }
        
        // Stickiness: If the recent history has code blocks, stay in coding mode
        // unless the user explicitly changes topic to something trivial or asks for a joke.
        if hasRecentCodeBlocks(history: lowerHistory) && !isTrivialChat(prompt: lowerPrompt) && !lowerPrompt.contains("joke") {
            print("[ModelRouter] Routing → BIG CODE MODEL (context stickiness)")
            return bigCode
        }

        // 4. Diagnostic/Debugging
        if isDiagnostic(prompt: lowerPrompt) {
            print("[ModelRouter] Routing → BIG CODE MODEL (diagnostic)")
            return bigCode
        }

        // 5. General Chat
        if isGeneralChat(prompt: lowerPrompt) {
            print("[ModelRouter] Routing → GENERAL CHAT (llama3)")
            return generalChat
        }

        // 6. Fast Model for short, simple queries
        if lowerPrompt.count < 100 && !hasRecentCodeBlocks(history: lowerHistory) {
            print("[ModelRouter] Routing → FAST MODEL (phi3/turbo)")
            return turbo
        }

        // 7. Default fallback
        print("[ModelRouter] Routing → FALLBACK (dolphin-llama3)")
        return "dolphin-llama3"
    }

    // MARK: - Parsing Helpers
    
    private func parsePrompt(_ prompt: String) -> (lastMessage: String, history: String) {
        // Helix prompts are formatted as "User: ...\nAssistant: ...\nUser: ..."
        // We want to split the last "User:" block from the rest.
        let components = prompt.components(separatedBy: "User: ")
        if let last = components.last, !last.isEmpty {
            let history = components.dropLast().joined(separator: "User: ")
            return (last, history)
        }
        return (prompt, "")
    }

    // MARK: - Heuristics

    private func isSeriousCoding(prompt: String) -> Bool {
        let strongIndicators = [
            "swift", "xcode", "compiler", "build failed",
            "error:", "exception", "traceback", "stack trace",
            "crashed", "debug", "async", "await",
            "func ", "class ", "struct ",
            "protocol ", "extension ",
            "```", // code block
            "return ", "init(", "var ", "let ",
            "refactor", "implement", "fix", "optimize"
        ]

        return strongIndicators.contains(where: { prompt.contains($0) })
    }
    
    private func hasRecentCodeBlocks(history: String) -> Bool {
        // Check if the last ~1000 chars of history contain code blocks
        let recentHistory = String(history.suffix(2000))
        return recentHistory.contains("```")
    }

    private func isDiagnostic(prompt: String) -> Bool {
        let diagnosticWords = [
            "why is", "what caused", "crash", "freeze",
            "log", "report", "trace", "wifi", "network",
            "ollama", "model isn't", "nothing happens",
            "it won't respond", "it doesn't work"
        ]

        return diagnosticWords.contains(where: { prompt.contains($0) })
    }

    private func isGeneralChat(prompt: String) -> Bool {
        let casualWords = [
            "what's", "how do", "explain", "tell me",
            "can you", "should i", "why does",
            "compare", "summarize", "walk me through"
        ]

        return casualWords.contains(where: { prompt.contains($0) })
    }
    
    private func isTrivialChat(prompt: String) -> Bool {
        let trivialWords = ["thanks", "ok", "cool", "got it", "hello", "hi", "bye"]
        return trivialWords.contains(where: { prompt.contains($0) }) && prompt.count < 20
    }

    private func isNSFWRequest(prompt: String) -> Bool {
        // "Offensive Security" is a valid technical term, not NSFW.
        if prompt.contains("offensive security") || prompt.contains("offensive cybersecurity") {
            return false
        }

        let nsfwIndicators = [
            "explicit", "nsfw", "dirty joke", "sexual", "sexually",
            "adult", "edgy", "dark humor", "dark joke",
            "uncensored", "no filter", "unfiltered",
            "inappropriate", "offensive", "raunchy",
            "profanity", "vulgar", "crude", "fuck",
            "joke", "tell me a joke" // Route all jokes to uncensored model to avoid "safe" refusals
        ]

        return nsfwIndicators.contains(where: { prompt.contains($0) })
    }
}

