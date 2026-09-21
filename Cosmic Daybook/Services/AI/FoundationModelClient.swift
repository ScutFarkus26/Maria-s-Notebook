//
//  FoundationModelClient.swift
//  Cosmic Daybook
//
//  Shared MCPClientProtocol plumbing for the two FoundationModels-backed
//  clients: on-device (`LocalModelClient`) and Private Cloud Compute
//  (`PrivateCloudModelClient`). Each client supplies only what differs — its
//  availability check and how it configures a session and its generation
//  options. The availability guard, instruction assembly, response handling,
//  JSON validation and error mapping live here, once.
//

import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

protocol FoundationModelClient: MCPClientProtocol {
    /// True when the backing model can accept requests right now.
    var isAvailable: Bool { get }

    /// Human-readable description of why the model is unavailable.
    var unavailabilityReason: String { get }

    /// A session configured for this client's model.
    func makeSession(instructions: String) -> LanguageModelSession

    /// The options this client sends with a single response request.
    func generationOptions(temperature: Double, maxTokens: Int?) -> GenerationOptions
}

// MARK: - Shared Request Handling

extension FoundationModelClient {

    /// Appended to instructions when the caller needs raw JSON back.
    static var jsonOnlyInstruction: String {
        "\n\nIMPORTANT: Return ONLY valid JSON. No markdown, no code blocks."
    }

    /// Throws `LocalModelError.unavailable` when the model cannot be reached.
    func requireAvailable() throws {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }
    }

    /// Plain-text response for `instructions` + `prompt`.
    func respond(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int?
    ) async throws -> String {
        try requireAvailable()

        let session = makeSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt,
                options: generationOptions(temperature: temperature, maxTokens: maxTokens)
            )
            return response.content
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    /// JSON response for `instructions` + `prompt`, validated before returning.
    func respondJSON(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int?
    ) async throws -> String {
        try requireAvailable()

        let session = makeSession(instructions: instructions + Self.jsonOnlyInstruction)

        do {
            let response = try await session.respond(
                to: prompt,
                options: generationOptions(temperature: temperature, maxTokens: maxTokens)
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
}

// MARK: - MCPClientProtocol

extension FoundationModelClient {

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await respond(
            prompt: prompt, instructions: AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: nil
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
        try await respond(
            prompt: prompt, instructions: systemMessage ?? AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: maxTokens
        )
    }

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await respondJSON(
            prompt: prompt, instructions: AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: nil
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
        try await respondJSON(
            prompt: prompt, instructions: systemMessage ?? AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: maxTokens
        )
    }
}

#endif
