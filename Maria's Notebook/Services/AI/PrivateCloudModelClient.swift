//
//  PrivateCloudModelClient.swift
//  Maria's Notebook
//
//  MCPClientProtocol implementation backed by Apple's server-side model on
//  Private Cloud Compute (PCC). Same privacy guarantees as on-device (stateless,
//  independently verifiable), but with a much larger context window and optional
//  reasoning — suited to big drafting jobs like report cards and weekly summaries.
//
//  Requires the managed entitlement `com.apple.developer.private-cloud-compute`
//  (request access at https://developer.apple.com/private-cloud-compute/).
//  Until granted, `availability` reports unavailable and callers fall back.
//

import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

/// Apple Private Cloud Compute AI client using the FoundationModels framework.
/// Falls back cleanly when PCC is unavailable (no entitlement, offline, quota).
final class PrivateCloudModelClient: MCPClientProtocol {
    private static let logger = Logger.ai

    private let model = PrivateCloudComputeLanguageModel()

    // MARK: - Availability

    /// Returns true if Private Cloud Compute is ready to accept requests.
    var isAvailable: Bool {
        model.isAvailable
    }

    /// Human-readable description of why PCC is unavailable.
    var unavailabilityReason: String {
        switch model.availability {
        case .available:
            return ""
        case .unavailable(.deviceNotEligible):
            return "This device cannot use Private Cloud Compute."
        case .unavailable(.systemNotReady):
            return "Private Cloud Compute is not ready. It needs Apple Intelligence, "
                + "a network connection, and the app's PCC entitlement."
        case .unavailable:
            return "Private Cloud Compute is not available."
        }
    }

    // MARK: - Draft Generation (PCC-specific)

    /// Generates a long-form draft with an explicit reasoning level.
    /// Use for big jobs (report cards, weekly summaries) where quality matters
    /// more than latency.
    func generateDraft(
        prompt: String,
        instructions: String,
        temperature: Double = 0.7,
        reasoning: ContextOptions.ReasoningLevel = .moderate
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                options: .init(temperature: temperature),
                contextOptions: ContextOptions(reasoningLevel: reasoning)
            )
            return response.content
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
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
        model claudeModel: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }

        let instructions = systemMessage ?? AIPrompts.generalAssistant
        let session = LanguageModelSession(model: model, instructions: instructions)

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
        model claudeModel: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }

        let instructions = (systemMessage ?? AIPrompts.generalAssistant)
            + "\n\nIMPORTANT: Return ONLY valid JSON. No markdown, no code blocks."
        let session = LanguageModelSession(model: model, instructions: instructions)

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
        [] // PCC has no external knowledge base
    }

    // sendConversation and streamConversation use the protocol default
    // implementations (message flattening).
}

#endif
