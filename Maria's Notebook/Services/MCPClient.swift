//
//  MCPClient.swift
//  Maria's Notebook
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
    
    /// Analyzes text and extracts patterns
    func analyzePatterns(text: String, context: String) async throws -> [String]

    /// Searches external knowledge bases (e.g., educational standards, curriculum frameworks)
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult]

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

    // Sends a multi-turn conversation with streaming, calling onDelta for each text chunk.
    // Returns the full response text when complete.
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
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
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        // Non-streaming fallback: generate full text, emit as single delta.
        let result = try await sendConversation(
            messages: messages,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            model: model,
            timeout: timeout
        )
        onDelta(result)
        return result
    }
}

/// Represents a result from an external knowledge base query
struct KnowledgeBaseResult: Codable {
    let title: String
    let summary: String
    let relevanceScore: Double
    let source: String
}

// MARK: - MCP Protocol Types

struct MCPRequest: Encodable {
    let method: String
    let params: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case method
        case params
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        
        // Convert params dictionary to JSON
        let paramsData = try JSONSerialization.data(withJSONObject: params)
        let paramsJSON = try JSONSerialization.jsonObject(with: paramsData)
        try container.encode(paramsJSON as? [String: String] ?? [:], forKey: .params)
    }
}

struct MCPResponse<T: Decodable>: Decodable {
    let result: T
    let metadata: MCPMetadata?
}

struct MCPMetadata: Decodable {
    let processingTime: Double?
    let model: String?
    let tokensUsed: Int?
}

enum MCPError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .serverError(let statusCode):
            return "MCP server error: HTTP \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode MCP response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
