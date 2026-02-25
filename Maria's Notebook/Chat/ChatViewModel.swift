import Foundation
import SwiftData
import OSLog

/// ViewModel for the Ask AI chat interface.
/// Manages session state, message sending, and error handling.
@Observable
@MainActor
final class ChatViewModel {
    private static let logger = Logger.ai

    // MARK: - State

    var inputText = ""
    var isLoading = false
    var errorMessage: String?

    private(set) var session: ChatSession?
    private var chatService: ChatService?

    // MARK: - Computed

    var messages: [ChatMessage] {
        session?.messages ?? []
    }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var hasAPIKey: Bool {
        AnthropicAPIClient.hasAPIKey()
    }

    // MARK: - Configuration

    /// Configure with dependencies. Called from the view's onAppear.
    func configure(modelContext: ModelContext, mcpClient: MCPClientProtocol) {
        guard chatService == nil else { return } // Already configured
        let service = ChatService(modelContext: modelContext, mcpClient: mcpClient)
        self.chatService = service
        self.session = service.startSession()
        Self.logger.debug("ChatViewModel configured")
    }

    // MARK: - Actions

    /// Sends the current input text as a user message.
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var currentSession = session, let service = chatService else { return }

        inputText = ""
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await service.sendMessage(text, session: &currentSession)
                self.session = currentSession
            } catch {
                Self.logger.warning("Chat send failed: \(error)")
                self.errorMessage = error.localizedDescription
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
    }
}
