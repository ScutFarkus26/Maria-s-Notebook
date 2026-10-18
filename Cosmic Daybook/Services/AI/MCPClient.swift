//
//  MCPClient.swift
//  Cosmic Daybook
//
//  The app's language-model client interface; AIClientRouter tries on-device, then opt-in Private Cloud Compute
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
    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String

    // Generates structured JSON with full configuration
    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String
    
    // Sends a multi-turn conversation and returns the assistant's response text.
    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval?
    ) async throws -> String
}

/// A model `AIClientRouter` can try: whether it can take a request now, and
/// why not, in the guide's words.
protocol RoutableModelClient: MCPClientProtocol {
    var isAvailable: Bool { get }
    var unavailabilityReason: String { get }
}

// MARK: - Default Implementations

// Fallbacks for clients that don't implement a form themselves. None of them
// takes default argument values: a call that left an argument out would bind
// to the fallback statically and skip the client's own implementation. Each
// forwards to a requirement, so the client's fullest form runs; only a client
// with nothing but the short forms loses the system message and token limit.
extension MCPClientProtocol {
    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?
    ) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: systemMessage,
            temperature: temperature, maxTokens: maxTokens,
            timeout: nil
        )
    }

    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?
    ) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: systemMessage,
            temperature: temperature, maxTokens: maxTokens,
            timeout: nil
        )
    }

    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await generateText(prompt: prompt, temperature: temperature)
    }

    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await generateStructuredJSON(prompt: prompt, temperature: temperature)
    }

    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval?
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
            timeout: timeout
        )
    }
}
