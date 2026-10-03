import Foundation
import CoreData
import OSLog

/// ViewModel for the Ask AI chat interface.
/// Manages session state, streaming, persistence, and dynamic suggestions.
/// Uses the model selected for Ask AI, with Apple Intelligence as the default.
@Observable
final class ChatViewModel {
    private static let logger = Logger.ai

    // MARK: - State

    var inputText = ""
    var isLoading = false
    var errorMessage: String?

    /// The current streaming assistant message content (updated as chunks arrive).
    var streamingContent: String?

    /// Whether we're actively receiving streamed text.
    var isStreaming: Bool { streamingContent != nil }

    private(set) var session: ChatSession?
    private var chatService: ChatService?
    /// Which classroom's saved chat this is (`ChatSession.storageKey`).
    private var sampleClassroom = false
    private var defaults: UserDefaults = .standard
    /// The answer being streamed, and which chat it belongs to. New Chat
    /// mid-answer cancels it and moves on a generation, so a late answer
    /// can't put the old chat back on screen or save it over the new one.
    private var sendTask: Task<Void, Never>?
    private var generation = 0

    // MARK: - Computed

    var messages: [ChatMessage] {
        session?.messages ?? []
    }

    var canSend: Bool {
        !inputText.trimmed().isEmpty && !isLoading
    }

    /// CDStudent names for dynamic suggested questions.
    var studentNames: [String] {
        session?.studentNames ?? []
    }

    /// Generates suggested questions using real student names when available.
    var suggestedQuestions: [String] {
        let names = studentNames
        if names.count >= 2 {
            let shuffled = names.shuffled()
            let name1 = shuffled[0]
            let name2 = shuffled[1]
            return [
                "How many students do I have?",
                "What lessons has \(name1) had recently?",
                "Who was absent this week?",
                "What can \(name1) and \(name2) work on together?"
            ]
        } else if let name = names.first {
            return [
                "How many students do I have?",
                "What lessons has \(name) had recently?",
                "Who was absent this week?",
                "Which students haven't had a presentation recently?"
            ]
        } else {
            return [
                "How many students do I have?",
                "Who was absent this week?",
                "What lessons have been given this week?",
                "Which students haven't had a presentation recently?"
            ]
        }
    }

    // MARK: - Configuration

    /// Configure with dependencies. Called from the view's onAppear.
    func configure(
        viewContext: NSManagedObjectContext,
        mcpClient: MCPClientProtocol,
        sampleClassroom: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        guard chatService == nil else { return } // Already configured
        let service = ChatService(modelContext: viewContext, mcpClient: mcpClient)
        self.chatService = service
        self.sampleClassroom = sampleClassroom
        self.defaults = defaults

        // Try to restore a saved session, otherwise start fresh
        if let saved = ChatSession.loadSaved(sampleClassroom: sampleClassroom, defaults: defaults) {
            self.session = saved
            // Refresh the snapshot since it's likely stale from a previous launch
            var restoredSession = saved
            restoredSession.messages.removeAll { $0.isEscalationPrompt }
            restoredSession.classroomSnapshotText = nil
            restoredSession.snapshotBuiltAt = nil
            self.session = restoredSession
            Self.logger.debug("ChatViewModel restored saved session with \(saved.messages.count) messages")
        } else {
            self.session = service.startSession()
        }

        Self.logger.debug("ChatViewModel configured")
    }

    // MARK: - Actions

    /// Sends the current input text as a user message with streaming.
    func sendMessage() {
        let text = inputText.trimmed()
        guard !text.isEmpty, var currentSession = session, let service = chatService else { return }

        inputText = ""
        isLoading = true
        errorMessage = nil
        streamingContent = ""

        // Show the user's message immediately. The service appends it to its own
        // copy of the session, which replaces this optimistic one on success.
        let preSendSession = currentSession
        var optimisticSession = currentSession
        optimisticSession.messages.append(ChatMessage(role: .user, content: text))
        session = optimisticSession

        let generation = generation
        sendTask = Task { [self] in
            // The answer so far, shown at most about ten times a second rather
            // than once per chunk; flushed before the stream's outcome lands.
            let throttle = StreamingTextThrottle { [weak self] answerSoFar in
                self?.streamingContent = answerSoFar
            }
            do {
                _ = try await service.sendMessageStreaming(
                    text,
                    session: &currentSession
                ) { answerSoFar in
                    throttle.submit(answerSoFar)
                }
                // New Chat was tapped meanwhile: this answer is the old chat's.
                guard generation == self.generation else { return }
                throttle.flush()
                self.session = currentSession
                self.streamingContent = nil

                // Persist after each message exchange
                currentSession.save(sampleClassroom: sampleClassroom, defaults: defaults)
            } catch {
                guard generation == self.generation else { return }
                throttle.flush()
                Self.logger.warning("Chat send failed: \(error)")
                // Roll back the optimistic message and put the text back in the
                // input field so the message isn't lost.
                self.session = preSendSession
                if self.inputText.isEmpty {
                    self.inputText = text
                }
                self.errorMessage = AppErrorMessages.aiMessage(
                    for: error, fallback: "Couldn't get an answer right now. Try again in a moment."
                )
                self.streamingContent = nil
            }
            self.isLoading = false
        }
    }

    /// Resets the chat session to start fresh.
    func resetSession() {
        guard let service = chatService else { return }
        generation += 1
        sendTask?.cancel()
        sendTask = nil
        session = service.startSession()
        errorMessage = nil
        inputText = ""
        streamingContent = nil
        isLoading = false
        ChatSession.clearSaved(sampleClassroom: sampleClassroom, defaults: defaults)
    }

    /// Returns once the answer being streamed, if any, has landed (tests).
    func waitForSend() async {
        await sendTask?.value
    }
}
