//
//  MCPClient.swift
//  Cosmic Daybook
//
//  MCP (Model Context Protocol) client for external AI tool integration
//

import Foundation

/// Protocol defining the interface for MCP tool interactions
protocol MCPClientProtocol {
    /// Generates text using MCP's language model tools
    func generateText(prompt: String, temperature: Double) async throws -> String
    
    /// Generates text with system message and configurable max tokens
    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?
    ) async throws -> String

    /// Generates structured JSON response using MCP's language model tools
    func generateStructuredJSON(
        prompt: String, temperature: Double
    ) async throws -> String

    /// Generates structured JSON with system message and max tokens
    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?
    ) async throws -> String

    // Generates text with full configuration including model and timeout
    // swiftlint:disable:next function_parameter_count
    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        model: String?, timeout: TimeInterval?
    ) async throws -> String

    // Generates structured JSON with full configuration
    // swiftlint:disable:next function_parameter_count
    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        model: String?, timeout: TimeInterval?
    ) async throws -> String
    
    // Sends a multi-turn conversation and returns the assistant's response text.
    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String

    // Sends a multi-turn conversation with streaming, calling onText with the
    // whole answer so far each time it grows (cumulative, never a delta).
    // Returns the full response text when complete.
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String

    /// Returns source records collected by the most recent grounded request.
    /// Providers without local notebook tools return an empty list.
    func consumeEvidenceSources() async -> [EvidenceReference]
}

// MARK: - Default Implementations

extension MCPClientProtocol {
    func consumeEvidenceSources() async -> [EvidenceReference] { [] }

    func generateText(
        prompt: String, systemMessage: String? = nil,
        temperature: Double, maxTokens: Int? = nil
    ) async throws -> String {
        try await generateText(prompt: prompt, temperature: temperature)
    }

    func generateStructuredJSON(
        prompt: String, systemMessage: String? = nil,
        temperature: Double, maxTokens: Int? = nil
    ) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, temperature: temperature
        )
    }

    func generateText(
        prompt: String, systemMessage: String? = nil,
        temperature: Double, maxTokens: Int? = nil,
        model: String? = nil, timeout: TimeInterval? = nil
    ) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: systemMessage,
            temperature: temperature, maxTokens: maxTokens
        )
    }

    func generateStructuredJSON(
        prompt: String, systemMessage: String? = nil,
        temperature: Double, maxTokens: Int? = nil,
        model: String? = nil, timeout: TimeInterval? = nil
    ) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: systemMessage,
            temperature: temperature, maxTokens: maxTokens
        )
    }

    func sendConversation(
        messages: [[String: String]],
        systemMessage: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        model: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        // Flatten multi-turn messages into a single prompt for clients
        // that don't support native multi-turn conversation.
        let flatPrompt = messages.map { "\($0["role"] ?? "user"): \($0["content"] ?? "")" }
            .joined(separator: "\n\n")
        return try await generateText(
            prompt: flatPrompt,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            model: model,
            timeout: timeout
        )
    }

    func streamConversation(
        messages: [[String: String]],
        systemMessage: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        model: String? = nil,
        timeout: TimeInterval? = nil,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        // Non-streaming fallback: generate full text, emit it once.
        let result = try await sendConversation(
            messages: messages,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            model: model,
            timeout: timeout
        )
        onText(result)
        return result
    }
}
