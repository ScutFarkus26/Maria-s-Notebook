import Foundation
import SwiftData
import OSLog

/// Orchestrates the chat flow: context assembly, API calls, and session management.
@MainActor
final class ChatService {
    private static let logger = Logger.ai

    private let modelContext: ModelContext
    private let mcpClient: MCPClientProtocol
    private let contextAssembler: ChatContextAssembler

    /// Maximum conversation messages to include in API requests (to stay within token budget).
    private let maxHistoryMessages = 10

    init(modelContext: ModelContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
        self.contextAssembler = ChatContextAssembler(context: modelContext)
    }

    // MARK: - Session Management

    /// Starts a new chat session and builds the initial classroom snapshot.
    func startSession() -> ChatSession {
        var session = ChatSession()
        session.classroomSnapshotText = contextAssembler.buildClassroomSnapshot()
        session.snapshotBuiltAt = Date()
        Self.logger.debug("Chat session started with classroom snapshot")
        return session
    }

    // MARK: - Send Message

    /// Sends a user message and returns the assistant's response.
    /// Mutates the session in-place with the new messages.
    func sendMessage(_ question: String, session: inout ChatSession) async throws -> String {
        // Refresh snapshot if stale
        if session.isSnapshotStale {
            session.classroomSnapshotText = contextAssembler.buildClassroomSnapshot()
            session.snapshotBuiltAt = Date()
        }

        // Add user message
        let userMessage = ChatMessage(role: .user, content: question)
        session.messages.append(userMessage)

        // Build question-specific context (Tier 2)
        let (questionContext, updatedMentionedIDs) = contextAssembler.buildQuestionContext(
            question: question,
            existingMentionedIDs: session.mentionedStudentIDs
        )
        session.mentionedStudentIDs = updatedMentionedIDs

        // Assemble system message
        let systemMessage = buildSystemMessage(
            snapshot: session.classroomSnapshotText ?? "",
            questionContext: questionContext
        )

        // Build messages array for API (keep within token budget)
        let apiMessages = buildAPIMessages(from: session.messages)

        // Call the API
        guard let client = mcpClient as? AnthropicAPIClient else {
            throw ChatError.serviceNotConfigured
        }

        let responseText = try await client.sendConversation(
            messages: apiMessages,
            systemMessage: systemMessage,
            temperature: 0.7,
            maxTokens: 2048
        )

        // Add assistant response to session
        let assistantMessage = ChatMessage(role: .assistant, content: responseText)
        session.messages.append(assistantMessage)

        Self.logger.debug("Chat response received (\(responseText.count) chars)")
        return responseText
    }

    // MARK: - Private Helpers

    private func buildSystemMessage(snapshot: String, questionContext: String) -> String {
        var parts = [AIPrompts.chatAssistant]

        if !snapshot.isEmpty {
            parts.append("\n\n\(snapshot)")
        }

        if !questionContext.isEmpty {
            parts.append("\n\(questionContext)")
        }

        return parts.joined()
    }

    /// Converts session messages to API format, pruning old messages to stay within budget.
    private func buildAPIMessages(from messages: [ChatMessage]) -> [[String: String]] {
        let recentMessages = messages.suffix(maxHistoryMessages)
        return recentMessages.map { message in
            ["role": message.role.rawValue, "content": message.content]
        }
    }
}

// MARK: - Chat Errors

enum ChatError: Error, LocalizedError {
    case serviceNotConfigured
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured:
            return "Chat service is not properly configured."
        case .noAPIKey:
            return "Please add your Anthropic API key in Settings to use Ask AI."
        }
    }
}
