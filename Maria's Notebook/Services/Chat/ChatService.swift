import Foundation
import CoreData
import OSLog

/// Orchestrates the chat flow: context assembly, API calls, and session management.
@MainActor
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

        // Add assistant response to session
        let assistantMessage = ChatMessage(role: .assistant, content: responseText)
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

        // Add the complete assistant response to session
        let assistantMessage = ChatMessage(role: .assistant, content: fullResponse)
        session.messages.append(assistantMessage)

        Self.logger.debug("Streaming chat response complete (\(fullResponse.count) chars)")
        return fullResponse
    }

    // MARK: - Cloud Escalation

    // Escalates a question to Claude after optimizing the prompt locally.
    // The local model refines the original question using its prior attempt, then
    // the optimized prompt is sent directly to Claude for a higher-quality answer.
    // swiftlint:disable:next function_body_length
    func escalateToCloud(
        originalQuestion: String,
        localResponse: String,
        session: inout ChatSession,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let router = mcpClient as? AIClientRouter else {
            throw ChatError.serviceNotConfigured
        }

        // Step 1: Use the local model to optimize the prompt for Claude
        let optimizationPrompt = """
        You are a prompt optimizer. Rewrite the following question to be clearer and more specific \
        for a powerful cloud AI assistant. Incorporate relevant context from the conversation. \
        Return ONLY the optimized question, nothing else.

        Original question: \(originalQuestion)

        Your previous answer (which was insufficient): \(localResponse.prefix(500))

        Optimized question:
        """

        // Try to optimize locally; fall back to the original question if local model is unavailable
        var optimizedQuestion = originalQuestion
        do {
            let localOptimized: String
            if await router.ollamaClient.isAvailable {
                localOptimized = try await router.ollamaClient.generateText(
                    prompt: optimizationPrompt, temperature: 0.3
                )
            } else {
                #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
                if #available(macOS 26.0, iOS 26.0, *), router.localClient.isAvailable {
                    localOptimized = try await router.localClient.generateText(
                        prompt: optimizationPrompt, temperature: 0.3
                    )
                } else {
                    localOptimized = originalQuestion
                }
                #else
                localOptimized = originalQuestion
                #endif
            }

            let trimmed = localOptimized.trimmed()
            if !trimmed.isEmpty {
                optimizedQuestion = trimmed
            }
        } catch {
            Self.logger.info("Local prompt optimization failed, using original question: \(error.localizedDescription)")
        }

        Self.logger.debug("Escalating to Claude with optimized prompt (\(optimizedQuestion.count) chars)")

        // Step 2: Build context and send directly to Claude
        let systemMessage = buildSystemMessage(
            snapshot: session.classroomSnapshotText ?? "",
            questionContext: ""
        )

        // Build messages including the optimized question as the latest user message
        var apiMessages = buildAPIMessages(from: session.messages)
        // Replace the last user message with the optimized version for Claude
        if let lastUserIndex = apiMessages.lastIndex(where: { $0["role"] == "user" }) {
            apiMessages[lastUserIndex] = ["role": "user", "content": optimizedQuestion]
        }

        let fullResponse = try await router.anthropicClient.streamConversation(
            messages: apiMessages,
            systemMessage: systemMessage,
            temperature: 0.7,
            maxTokens: 2048,
            model: nil,
            timeout: nil,
            onDelta: onDelta
        )

        // Add the cloud response to session
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: fullResponse,
            modelID: AIModelOption.claudeSonnet.rawValue
        )
        session.messages.append(assistantMessage)

        Self.logger.debug("Cloud escalation complete (\(fullResponse.count) chars)")
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
