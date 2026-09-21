//
//  PrivateCloudModelClient.swift
//  Cosmic Daybook
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
final class PrivateCloudModelClient: FoundationModelClient {
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
        try requireAvailable()

        let session = makeSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                options: generationOptions(temperature: temperature, maxTokens: nil),
                contextOptions: ContextOptions(reasoningLevel: reasoning)
            )
            return response.content
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    // MARK: - FoundationModelClient

    /// Private Cloud Compute session: same API as on-device, PCC model.
    func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: instructions)
    }

    /// PCC sizes its own responses, so `maxTokens` is deliberately unused.
    func generationOptions(temperature: Double, maxTokens: Int?) -> GenerationOptions {
        .init(temperature: temperature)
    }

    // sendConversation and streamConversation use the protocol default
    // implementations (message flattening).
}

#endif
