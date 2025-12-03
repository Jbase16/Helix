import SwiftUI
import Combine
import Foundation

@MainActor
final class HelixAppState: ObservableObject {

    /// All chat threads saved in the app.  The first thread is selected by default.
    @Published var threads: [ChatThread]

    /// Identifier of the currently active thread.  If nil there are no threads.
    @Published var selectedThreadID: UUID?

    /// Whether the LLM is currently generating output.
    @Published var isProcessing: Bool = false

    /// Any error produced by the model or network.  When set, the UI should present an alert.
    @Published var currentError: HelixError?

    private let llm: LLMService
    private let agentLoop: AgentLoopService
    private var cancellables = Set<AnyCancellable>()

    // File on disk where threads are persisted.
    private let threadsURL: URL = {
        // Attempt to write to Application Support/HelixAgent/threads.json
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("HelixAgent", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("threads.json", isDirectory: false)
    }()

    /// The current tool call waiting for user approval.
    @Published var pendingAction: ToolCall?
    
    /// Continuation to resume the agent loop after approval/rejection.
    private var permissionContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Init

    /// Convenience init that creates a default `LLMService`.
    convenience init() {
        self.init(llm: LLMService())
    }

    /// Designated initializer.  Accepts an `LLMService` for easier testing.
    init(llm: LLMService) {
        self.llm = llm
        self.agentLoop = AgentLoopService(llm: llm)
        
        // Load any saved threads; if none exist, start with one main thread.
        if let loaded = Self.loadThreads(from: threadsURL), !loaded.isEmpty {
            self.threads = loaded
            self.selectedThreadID = loaded.first?.id
        } else {
            let thread = ChatThread(title: "Main Chat", messages: [])
            self.threads = [thread]
            self.selectedThreadID = thread.id
        }

        // Keep isProcessing in sync with the LLM service state.
        llm.$isGenerating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] generating in
                self?.isProcessing = generating
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    /// Save the current set of threads to disk.
    private func save() {
        do {
            let data = try JSONEncoder().encode(threads)
            try data.write(to: threadsURL, options: [.atomic])
        } catch {
            print("[HelixAppState] Failed to save threads: \(error)")
        }
    }

    /// Load threads from disk if available.
    private static func loadThreads(from url: URL) -> [ChatThread]? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ChatThread].self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Thread Management

    /// Create a new chat thread and select it.
    func createThread(title: String = "New Chat") {
        let newThread = ChatThread(title: title)
        threads.append(newThread)
        selectedThreadID = newThread.id
        save()
    }

    /// Delete a chat thread by its id.  If it is the last thread, a new one is created.
    func deleteThread(id: UUID) {
        if let idx = threads.firstIndex(where: { $0.id == id }) {
            threads.remove(at: idx)
            if threads.isEmpty {
                let newThread = ChatThread(title: "Main Chat")
                threads = [newThread]
            }
            selectedThreadID = threads.first?.id
            save()
        }
    }

    /// Select a thread by its id.
    func selectThread(id: UUID) {
        if threads.contains(where: { $0.id == id }) {
            selectedThreadID = id
        }
    }

    /// Returns the currently selected thread, if any.
    var currentThread: ChatThread? {
        get {
            guard let id = selectedThreadID else { return nil }
            return threads.first(where: { $0.id == id })
        }
        set {
            guard let newValue else { return }
            if let idx = threads.firstIndex(where: { $0.id == newValue.id }) {
                threads[idx] = newValue
                save()
            }
        }
    }

    // MARK: - Public API

    /// Reset the current conversation to an empty thread.
    func clear() {
        guard var thread = currentThread else { return }
        thread.clear()
        currentThread = thread
    }

    /// Send a user message and stream an assistant reply into the selected thread.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var thread = currentThread else { return }

        // 1. Append user message using ChatThread.append() to update lastUpdated.
        let userMessage = ChatMessage(role: .user, text: trimmed)
        thread.append(userMessage)

        // 2. Append placeholder assistant message we'll stream into.
        let assistantPlaceholder = ChatMessage(role: .assistant, text: "")
        thread.append(assistantPlaceholder)
        let replyID = assistantPlaceholder.id
        currentThread = thread

        // 3. Kick off Agent Loop.
        // We pass all messages EXCEPT the placeholder we just added, because the agent loop will generate that response.
        let historyForAgent = thread.messages.dropLast() // Remove the empty placeholder
        
        agentLoop.run(history: Array(historyForAgent), onToken: { [weak self] token in
            guard let self else { return }
            guard var thread = self.currentThread else { return }
            if let index = thread.messages.firstIndex(where: { $0.id == replyID }) {
                thread.messages[index].text.append(token)
                self.currentThread = thread
            }
        }, onRequestPermission: { [weak self] toolCall in
            return await withCheckedContinuation { continuation in
                Task { @MainActor in
                    self?.pendingAction = toolCall
                    self?.permissionContinuation = continuation
                }
            }
        }, onError: { [weak self] error in
            Task { @MainActor in
                self?.currentError = error
            }
        }, onComplete: { [weak self] in
            // Save the conversation when complete
            self?.save()
        })
    }
    
    /// Approve the pending action.
    func approvePendingAction() {
        pendingAction = nil
        permissionContinuation?.resume(returning: true)
        permissionContinuation = nil
    }
    
    /// Reject the pending action.
    func rejectPendingAction() {
        pendingAction = nil
        permissionContinuation?.resume(returning: false)
        permissionContinuation = nil
    }

    /// Cancel any in-flight LLM generation.
    func cancelGeneration() {
        llm.cancel()
        // If waiting for permission, cancel that too
        if permissionContinuation != nil {
            rejectPendingAction()
        }
    }
}

