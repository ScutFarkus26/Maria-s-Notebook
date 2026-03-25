import Foundation
import SwiftData
import OSLog

/// ViewModel for the Ask AI chat interface.
/// Manages session state, streaming, persistence, and dynamic suggestions.
/// Handles smart local-first routing with user-driven cloud escalation.
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

    /// Holds the context for a pending cloud escalation (original question + local response).
    private(set) var pendingEscalation: PendingEscalation?

    /// Whether we're currently escalating to Claude.
    private(set) var isEscalating = false

    private(set) var session: ChatSession?
    private var chatService: ChatService?

    // MARK: - Escalation Types

    struct PendingEscalation {
        let originalQuestion: String
        let localResponse: String
    }

    // MARK: - Computed

    var messages: [ChatMessage] {
        session?.messages ?? []
    }

    var canSend: Bool {
        !inputText.trimmed().isEmpty && !isLoading
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
    /// After receiving a local response, validates quality and offers cloud escalation if needed.
    func sendMessage() {
        let text = inputText.trimmed()
        guard !text.isEmpty, var currentSession = session, let service = chatService else { return }

        // Capture the model before sending so we know which model was used
        let resolvedModel = AIFeatureArea.chat.resolvedModel()
        let resolvedModelID = resolvedModel.rawValue

        inputText = ""
        isLoading = true
        errorMessage = nil
        streamingContent = ""
        pendingEscalation = nil

        Task {
            do {
                let fullResponse = try await service.sendMessageStreaming(
                    text,
                    session: &currentSession
                ) { [weak self] delta in
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

                // Smart escalation: validate local response quality and offer cloud upgrade
                if resolvedModel == .localFirstAuto && AnthropicAPIClient.hasAPIKey() {
                    let validation = ResponseQualityValidator.validate(fullResponse, forRequest: text)
                    if !validation.isAdequate {
                        let reason = validation.reason ?? "unknown"
                        Self.logger.info("Local response inadequate (\(reason)), offering cloud escalation")
                        self.pendingEscalation = PendingEscalation(
                            originalQuestion: text,
                            localResponse: fullResponse
                        )
                        // Append an escalation prompt message to the session
                        let escalationMessage = ChatMessage(
                            role: .assistant,
                            content: "This answer might be improved with Claude. Want me to try?",
                            isEscalationPrompt: true
                        )
                        self.session?.messages.append(escalationMessage)
                    }
                }

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

    /// Accepts the cloud escalation offer. Uses local model to optimize the prompt,
    /// then sends the optimized request to Claude.
    func acceptEscalation() {
        guard let escalation = pendingEscalation,
              var currentSession = session,
              let service = chatService else { return }

        // Remove the escalation prompt message
        currentSession.messages.removeAll { $0.isEscalationPrompt }
        session = currentSession

        pendingEscalation = nil
        isEscalating = true
        isLoading = true
        streamingContent = ""
        errorMessage = nil

        Task {
            do {
                _ = try await service.escalateToCloud(
                    originalQuestion: escalation.originalQuestion,
                    localResponse: escalation.localResponse,
                    session: &currentSession
                ) { [weak self] delta in
                    Task { @MainActor in
                        self?.streamingContent = (self?.streamingContent ?? "") + delta
                    }
                }
                self.session = currentSession
                self.streamingContent = nil
                currentSession.save()
            } catch {
                Self.logger.warning("Cloud escalation failed: \(error)")
                self.errorMessage = error.localizedDescription
                self.streamingContent = nil
            }
            self.isLoading = false
            self.isEscalating = false
        }
    }

    /// Dismisses the cloud escalation offer without sending to Claude.
    func dismissEscalation() {
        pendingEscalation = nil
        // Remove the escalation prompt message from session
        session?.messages.removeAll { $0.isEscalationPrompt }
    }

    /// Resets the chat session to start fresh.
    func resetSession() {
        guard let service = chatService else { return }
        session = service.startSession()
        errorMessage = nil
        inputText = ""
        streamingContent = nil
        pendingEscalation = nil
        isEscalating = false
        ChatSession.clearSaved()
    }
}
