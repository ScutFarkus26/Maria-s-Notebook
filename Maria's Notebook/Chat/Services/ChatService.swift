import Foundation
import CoreData
import OSLog

/// Orchestrates the chat flow: context assembly, API calls, and session management.
final class ChatService {
    private static let logger = Logger.ai

    private let modelContext: NSManagedObjectContext
    private let mcpClient: MCPClientProtocol
    private let contextAssembler: ChatContextAssembler

    /// Maximum conversation messages to include in API requests (to stay within token budget).
    private let maxHistoryMessages = 10

    init(modelContext: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
        self.contextAssembler = ChatContextAssembler(context: modelContext)
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

    // MARK: - Session Management

    /// Starts a new chat session and builds the initial classroom snapshot.
    func startSession() -> ChatSession {
        var session = ChatSession()
        session.classroomSnapshotText = contextAssembler.buildClassroomSnapshot()
        session.snapshotBuiltAt = Date()

        // Populate student names for dynamic suggested questions
        let queryService = DataQueryService(context: modelContext)
        let students = queryService.fetchAllStudents(excludeTest: true)
        session.studentNames = students.map(\.firstName)

        Self.logger.debug("Chat session started with classroom snapshot")
        return session
    }

    // MARK: - Send Message (Non-Streaming)

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

        // Configure router for chat feature area and call through protocol
        mcpClient.configureForFeature(.chat)
        let chatModelID = AIFeatureArea.chat.resolvedClaudeModelID()

        let responseText = try await mcpClient.sendConversation(
            messages: apiMessages,
            systemMessage: systemMessage,
            temperature: 0.7,
            maxTokens: 2048,
            model: chatModelID
        )
        let sources = await mcpClient.consumeEvidenceSources()

        // Add assistant response to session
        let assistantMessage = ChatMessage(role: .assistant, content: responseText, sources: sources)
        session.messages.append(assistantMessage)

        Self.logger.debug("Chat response received (\(responseText.count) chars)")
        return responseText
    }

    // MARK: - Send Message (Streaming)

    /// Sends a user message with streaming. Calls onDelta for each text chunk.
    /// Adds a placeholder assistant message immediately and updates it as text arrives.
    /// Returns the message ID of the streaming assistant message so the caller can track it.
    func sendMessageStreaming(
        _ question: String,
        session: inout ChatSession,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
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

        // Configure router for chat feature area and stream through protocol
        mcpClient.configureForFeature(.chat)
        let chatModelID = AIFeatureArea.chat.resolvedClaudeModelID()

        let fullResponse = try await mcpClient.streamConversation(
            messages: apiMessages,
            systemMessage: systemMessage,
            temperature: 0.7,
            maxTokens: 2048,
            model: chatModelID,
            onDelta: onDelta
        )
        let sources = await mcpClient.consumeEvidenceSources()

        // Add the complete assistant response to session
        let assistantMessage = ChatMessage(role: .assistant, content: fullResponse, sources: sources)
        session.messages.append(assistantMessage)

        Self.logger.debug("Streaming chat response complete (\(fullResponse.count) chars)")
        return fullResponse
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
    /// Filters out escalation prompt messages (they're UI-only, not part of conversation context).
    private func buildAPIMessages(from messages: [ChatMessage]) -> [[String: String]] {
        let recentMessages = messages
            .filter { !$0.isEscalationPrompt }
            .suffix(maxHistoryMessages)
        return recentMessages.map { message in
            ["role": message.role.rawValue, "content": message.content]
        }
    }
}
