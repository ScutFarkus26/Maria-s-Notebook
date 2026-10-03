//
//  LocalModelClient.swift
//  Cosmic Daybook
//
//  MCPClientProtocol implementation backed by Apple's on-device FoundationModels.
//  Guarded behind ENABLE_FOUNDATION_MODELS flag (see Documentation/Architecture/AI.md).
//

import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

/// On-device AI client using Apple Intelligence via FoundationModels framework.
/// Falls back cleanly when Apple Intelligence is unavailable (wrong device, not enabled, etc.).
@available(macOS 26.0, iOS 26.0, *)
final class LocalModelClient: FoundationModelClient {
    private let evidenceSourceCollector = EvidenceSourceCollector()

    // MARK: - Availability

    /// Returns true if the on-device model is ready to accept requests.
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Human-readable description of why the model is unavailable.
    var unavailabilityReason: String {
        AppleIntelligenceMessages.unavailableMessage(for: SystemLanguageModel.default.availability) ?? ""
    }

    // MARK: - FoundationModelClient

    /// On-device session: the default system model, no tools attached.
    func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    func generationOptions(temperature: Double, maxTokens: Int?) -> GenerationOptions {
        .init(temperature: temperature, maximumResponseTokens: maxTokens)
    }

    // MARK: - Chat with notebook tools ("ask your notebook")

    // Answers conversational questions with notebook lookup tools attached, so the
    // model can search the teacher's own notes/lessons/students while answering —
    // fully on-device.

    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval?
    ) async throws -> String {
        try requireAvailable()
        let chat = await makeChatSession(messages: messages, systemMessage: systemMessage)
        do {
            let response = try await chat.session.respond(
                to: chat.prompt,
                options: generationOptions(temperature: temperature, maxTokens: maxTokens)
            )
            return response.content
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        try requireAvailable()
        let chat = await makeChatSession(messages: messages, systemMessage: systemMessage)
        do {
            let stream = chat.session.streamResponse(
                to: chat.prompt,
                options: generationOptions(temperature: temperature, maxTokens: maxTokens)
            )
            // Snapshots are cumulative: hand each one on whole when it adds a
            // character, rather than cutting a delta the caller re-appends.
            var emitted = ""
            for try await snapshot in stream {
                let full = snapshot.content
                if full.count > emitted.count {
                    emitted = full
                    onText(emitted)
                }
            }
            return emitted
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    func consumeEvidenceSources() async -> [EvidenceReference] {
        await evidenceSourceCollector.consume()
    }

    // Builds the session for one chat turn: notebook tools attached, prior turns
    // folded into the instructions, and the prompt to send with it.
    private func makeChatSession(
        messages: [[String: String]],
        systemMessage: String?
    ) async -> (session: LanguageModelSession, prompt: String) {
        _ = await evidenceSourceCollector.consume()
        let base = systemMessage ?? AIPrompts.chatAssistant
        let instructions = Self.conversationInstructions(from: messages, base: base)
        let session = LanguageModelSession(
            tools: NotebookTools.chatTools(sourceCollector: evidenceSourceCollector),
            instructions: instructions
        )
        return (session, Self.lastUserMessage(from: messages))
    }

    // Returns the most recent user message to use as the prompt.
    private static func lastUserMessage(from messages: [[String: String]]) -> String {
        messages.last(where: { $0["role"] == "user" })?["content"] ?? ""
    }

    // Injects all prior turns into session instructions so LanguageModelSession
    // sees a real conversation context rather than a flattened string prompt.
    private static func conversationInstructions(
        from messages: [[String: String]],
        base: String
    ) -> String {
        guard let lastUserIdx = messages.lastIndex(where: { $0["role"] == "user" }),
              lastUserIdx > 0 else {
            return base
        }
        let lines = messages.prefix(lastUserIdx).compactMap { msg -> String? in
            guard let role = msg["role"], let content = msg["content"], !content.isEmpty else { return nil }
            return role == "assistant" ? "Assistant: \(content)" : "Teacher: \(content)"
        }
        guard !lines.isEmpty else { return base }
        return base
            + "\n\n=== Prior conversation ===\n"
            + lines.joined(separator: "\n")
            + "\n=== End of prior conversation ==="
    }
}

// MARK: - Errors

nonisolated enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    /// Shown to the teacher as is, so every case is a plain sentence:
    /// `unavailable` carries one already, and `generationFailed` carries the
    /// translated message (the raw text goes to the log where it's caught).
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.isEmpty ? AppleIntelligenceMessages.notAvailable : reason
        case .contextTooLarge:
            return AppleIntelligenceMessages.tooLong
        case .rateLimited:
            return AppleIntelligenceMessages.busy
        case .invalidJSON:
            return AppleIntelligenceMessages.unreadable
        case .generationFailed(let message):
            return message
        }
    }

    /// Maps FoundationModels.LanguageModelError to LocalModelError.
    static func fromLanguageModel(_ error: LanguageModelError) -> LocalModelError {
        switch error {
        case .contextSizeExceeded:
            return .contextTooLarge
        case .rateLimited:
            return .rateLimited
        default:
            return .generationFailed(AppleIntelligenceMessages.message(for: error))
        }
    }
}

#else

// MARK: - Stub when FoundationModels is unavailable

/// Placeholder error type available regardless of FoundationModels flag.
/// Used by AIClientRouter to compile on all platforms.
nonisolated enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.isEmpty ? AppleIntelligenceMessages.notAvailable : reason
        case .contextTooLarge:
            return AppleIntelligenceMessages.tooLong
        case .rateLimited:
            return AppleIntelligenceMessages.busy
        case .invalidJSON:
            return AppleIntelligenceMessages.unreadable
        case .generationFailed(let message):
            return message
        }
    }
}

#endif
