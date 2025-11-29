import SwiftUI
import Combine
import Foundation

@MainActor
final class HelixAppState: ObservableObject {

    // Single main chat thread for now
    @Published var thread: ChatThread
    @Published var isProcessing: Bool = false

    private let llm: LLMService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    convenience init() {
        self.init(llm: LLMService())
    }

    init(llm: LLMService) {
        self.llm = llm
        self.thread = ChatThread(title: "Main Chat", messages: [])

        // Keep isProcessing in sync with the LLM service state.
        llm.$isGenerating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] generating in
                self?.isProcessing = generating
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Reset the conversation to an empty main thread.
    func clear() {
        thread = ChatThread(title: "Main Chat", messages: [])
    }

    /// Send a user message and stream an assistant reply into the thread.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Append user message.
        let userMessage = ChatMessage(role: .user, text: trimmed)
        thread.messages.append(userMessage)

        // 2. Append placeholder assistant message we'll stream into.
        let reply = ChatMessage(role: .assistant, text: "")
        thread.messages.append(reply)
        let replyID = reply.id

        // 3. Kick off generation. LLMService guarantees `onToken`
        //    is called on the main actor, so it is safe to mutate state here.
        llm.generate(prompt: trimmed) { [weak self] token in
            guard let self else { return }

            guard let index = self.thread.messages.firstIndex(where: { $0.id == replyID }) else {
                return
            }

            // Update the assistant message text in place.
            self.thread.messages[index].text.append(token)
        }
    }

    /// Cancel any in-flight LLM generation.
    func cancelGeneration() {
        llm.cancel()
    }
}
