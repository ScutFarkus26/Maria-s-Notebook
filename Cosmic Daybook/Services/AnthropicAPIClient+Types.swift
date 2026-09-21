//
//  AnthropicAPIClient+Types.swift
//  Cosmic Daybook
//
//  The request configuration and error type of the Anthropic client.
//

import Foundation

// MARK: - Request Configuration

extension AnthropicAPIClient {

    struct ClaudeRequestConfig {
        let model: String
        let maxTokens: Int
        let temperature: Double
        let timeout: TimeInterval
        let stream: Bool

        init(
            model: String, maxTokens: Int, temperature: Double,
            timeout: TimeInterval, stream: Bool = false
        ) {
            self.model = model; self.maxTokens = maxTokens; self.temperature = temperature
            self.timeout = timeout; self.stream = stream
        }
    }
}

// MARK: - Errors

enum AnthropicAPIError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case invalidResponseFormat
    case invalidJSON(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Anthropic API key not configured. Please add your API key in Settings."
        case .invalidResponse:
            return "Invalid response from Anthropic API"
        case .invalidResponseFormat:
            return "Unexpected response format from Anthropic API"
        case .invalidJSON(let json):
            return "Claude returned invalid JSON: \(json.prefix(100))..."
        case .apiError(let statusCode, let message):
            return "Anthropic API error (\(statusCode)): \(message)"
        }
    }
}
