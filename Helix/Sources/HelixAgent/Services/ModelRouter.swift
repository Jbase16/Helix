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
    private let nsfw = "wizardlm-uncensored:13b"      // explicit/NSFW/edgy content

    // MARK: - Routing Entry Point
    func modelName(for prompt: String) -> String {
        let lower = prompt.lowercased()

        // 1. If it's NSFW/explicit/edgy → WizardLM Uncensored
        if isNSFWRequest(prompt: lower) {
            print("[ModelRouter] Routing → NSFW MODEL (wizardlm-uncensored)")
            return nsfw
        }

        // 2. If it's REAL code or a true coding request → heavy coder
        if isSeriousCoding(prompt: lower) {
            print("[ModelRouter] Routing → BIG CODE MODEL")
            return bigCode
        }

        // 2. If you're troubleshooting, debugging, explaining logs
        if isDiagnostic(prompt: lower) {
            print("[ModelRouter] Routing → BIG CODE MODEL (diagnostic)")
            return bigCode
        }

        // 3. If you're asking a normal question, planning, chatting
        if isGeneralChat(prompt: lower) {
            print("[ModelRouter] Routing → GENERAL CHAT (llama3)")
            return generalChat
        }

        // 4. If it's short, utility, or single-step → turbo
        if lower.count < 100 {
            print("[ModelRouter] Routing → FAST MODEL (phi3)")
            return turbo
        }

        // 5. Default fallback → Llama3
        print("[ModelRouter] Routing → FALLBACK (llama3)")
        return generalChat
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
            "return ", "init(", "var ", "let "
        ]

        return strongIndicators.contains(where: { prompt.contains($0) })
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

    private func isNSFWRequest(prompt: String) -> Bool {
        let nsfwIndicators = [
            "explicit", "nsfw", "dirty joke", "sexual", "sexually",
            "adult", "edgy", "dark humor", "dark joke",
            "uncensored", "no filter", "unfiltered",
            "inappropriate", "offensive", "raunchy",
            "profanity", "vulgar", "crude", "fuck"
        ]

        return nsfwIndicators.contains(where: { prompt.contains($0) })
    }
}

