//
//  LocalModelClient.swift
//  Maria's Notebook
//
//  MCPClientProtocol implementation backed by Apple's on-device FoundationModels.
//  Guarded behind ENABLE_FOUNDATION_MODELS flag (see Docs/ENABLE_FOUNDATION_MODELS.md).
//

import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

/// On-device AI client using Apple Intelligence via FoundationModels framework.
/// Falls back cleanly when Apple Intelligence is unavailable (wrong device, not enabled, etc.).
@available(macOS 26.0, iOS 26.0, *)
final class LocalModelClient: MCPClientProtocol {
    private static let logger = Logger.ai

    // MARK: - Availability

    /// Returns true if the on-device model is ready to accept requests.
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Human-readable description of why the model is unavailable.
    var unavailabilityReason: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Enable Apple Intelligence in Settings."
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading. Try again later."
        case .unavailable:
            return "Apple Intelligence is not available."
        }
    }

    // MARK: - MCPClientProtocol

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: nil, temperature: temperature,
            maxTokens: nil, model: nil, timeout: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    func generateText(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }

        let instructions = systemMessage ?? AIPrompts.generalAssistant
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt,
                options: .init(temperature: temperature)
            )
            return response.content
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: nil, temperature: temperature,
            maxTokens: nil, model: nil, timeout: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    func generateStructuredJSON(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }

        let instructions = (systemMessage ?? AIPrompts.generalAssistant)
            + "\n\nIMPORTANT: Return ONLY valid JSON. No markdown, no code blocks."
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt,
                options: .init(temperature: temperature)
            )

            // Validate JSON
            let text = response.content.trimmed()
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8))
            return text
        } catch let error as LocalModelError {
            throw error
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        } catch {
            throw LocalModelError.invalidJSON
        }
    }

    func analyzePatterns(text: String, context: String) async throws -> [String] {
        let prompt = """
        Analyze the following text and identify 3-5 key patterns.
        Context: \(context)
        Text: \(text)
        Return ONLY a JSON array of strings.
        """
        let json = try await generateStructuredJSON(prompt: prompt, temperature: 0.3)
        return try JSONDecoder().decode([String].self, from: Data(json.utf8))
    }

    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        [] // On-device model has no external knowledge base
    }

    // MARK: - Chat with notebook tools ("ask your notebook")

    // Answers conversational questions with notebook lookup tools attached, so the
    // model can search the teacher's own notes/lessons/students while answering —
    // fully on-device.

    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            tools: NotebookTools.chatTools(),
            instructions: systemMessage ?? AIPrompts.chatAssistant
        )
        do {
            let response = try await session.respond(
                to: Self.flatten(messages),
                options: .init(temperature: temperature)
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
        model: String?,
        timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }
        let session = LanguageModelSession(
            tools: NotebookTools.chatTools(),
            instructions: systemMessage ?? AIPrompts.chatAssistant
        )
        do {
            let stream = session.streamResponse(
                to: Self.flatten(messages),
                options: .init(temperature: temperature)
            )
            // Snapshots are cumulative; emit only the new suffix as the delta.
            var emitted = ""
            for try await snapshot in stream {
                let full = snapshot.content
                if full.count > emitted.count {
                    onDelta(String(full.dropFirst(emitted.count)))
                    emitted = full
                }
            }
            return emitted
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    private static func flatten(_ messages: [[String: String]]) -> String {
        messages.map { "\($0["role"] ?? "user"): \($0["content"] ?? "")" }
            .joined(separator: "\n\n")
    }
}

// MARK: - Errors

enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "On-device model unavailable: \(reason)"
        case .contextTooLarge:
            return "Input too large for on-device processing. Try selecting fewer items."
        case .rateLimited:
            return "On-device model rate limited. Try again shortly."
        case .invalidJSON:
            return "On-device model returned invalid JSON."
        case .generationFailed(let msg):
            return "Generation failed: \(msg)"
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
            return .generationFailed(error.localizedDescription)
        }
    }
}

#else

// MARK: - Stub when FoundationModels is unavailable

/// Placeholder error type available regardless of FoundationModels flag.
/// Used by AIClientRouter to compile on all platforms.
enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "On-device model unavailable: \(reason)"
        case .contextTooLarge:
            return "Input too large for on-device processing."
        case .rateLimited:
            return "On-device model rate limited."
        case .invalidJSON:
            return "On-device model returned invalid JSON."
        case .generationFailed(let msg):
            return "Generation failed: \(msg)"
        }
    }
}

#endif
