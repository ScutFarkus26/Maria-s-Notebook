import Foundation
import SwiftData
import OSLog

/// ViewModel for the Ask AI chat interface.
/// Manages session state, streaming, persistence, and dynamic suggestions.
@Observable
@MainActor
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

    // MARK: - Computed

    var messages: [ChatMessage] {
        session?.messages ?? []
    }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    /// The currently configured AI model for the chat feature area.
    var currentModel: AIModelOption {
        AIFeatureArea.chat.resolvedModel()
    }

    /// Whether the current model needs an API key and one is configured.
    var needsAPIKey: Bool {
        currentModel.requiresAPIKey && !AnthropicAPIClient.hasAPIKey()
    }

    var hasAPIKey: Bool {
        AnthropicAPIClient.hasAPIKey()
    }

    /// Student names for dynamic suggested questions.
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
                "What can \(name1) and \(name2) work on together?",
            ]
        } else if let name = names.first {
            return [
                "How many students do I have?",
                "What lessons has \(name) had recently?",
                "Who was absent this week?",
                "Which students haven't had a presentation recently?",
            ]
        } else {
            return [
                "How many students do I have?",
                "Who was absent this week?",
                "What lessons have been given this week?",
                "Which students haven't had a presentation recently?",
            ]
        }
    }

    // MARK: - Configuration

    /// Configure with dependencies. Called from the view's onAppear.
    func configure(modelContext: ModelContext, mcpClient: MCPClientProtocol) {
        guard chatService == nil else { return } // Already configured
        let service = ChatService(modelContext: modelContext, mcpClient: mcpClient)
        self.chatService = service

        // Try to restore a saved session, otherwise start fresh
        if let saved = ChatSession.loadSaved() {
            self.session = saved
            // Refresh the snapshot since it's likely stale from a previous launch
            var restoredSession = saved
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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var currentSession = session, let service = chatService else { return }

        // Capture the model before sending so we know which model was used
        let resolvedModelID = AIFeatureArea.chat.resolvedModel().rawValue

        inputText = ""
        isLoading = true
        errorMessage = nil
        streamingContent = ""

        Task {
            do {
                _ = try await service.sendMessageStreaming(text, session: &currentSession) { [weak self] delta in
                    Task { @MainActor in
                        self?.streamingContent = (self?.streamingContent ?? "") + delta
                    }
                }
                // Tag the last assistant message with the model that generated it
                if let lastIndex = currentSession.messages.indices.last,
                   currentSession.messages[lastIndex].role == .assistant {
                    currentSession.messages[lastIndex].modelID = resolvedModelID
                }
                self.session = currentSession
                self.streamingContent = nil
                // Persist after each message exchange
                currentSession.save()
            } catch {
                Self.logger.warning("Chat send failed: \(error)")
                self.errorMessage = error.localizedDescription
                self.streamingContent = nil
            }
            self.isLoading = false
        }
    }

    /// Resets the chat session to start fresh.
    func resetSession() {
        guard let service = chatService else { return }
        session = service.startSession()
        errorMessage = nil
        inputText = ""
        streamingContent = nil
        ChatSession.clearSaved()
    }
}
