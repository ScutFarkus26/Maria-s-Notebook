//
//  AnthropicAPIClient.swift
//  Maria's Notebook
//
//  Direct Anthropic API client for student analysis
//

// swiftlint:disable file_length
import Foundation
import OSLog

// swiftlint:disable type_body_length
/// Direct implementation that connects to Anthropic's Claude API
final class AnthropicAPIClient: MCPClientProtocol {
    private static let logger = Logger.ai

    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL
    
    init(apiKey: String? = nil, session: URLSession = .shared) {
        // Try to load API key from UserDefaults, then from keychain, then use provided
        self.apiKey = apiKey ?? Self.loadAPIKey()
        self.session = session
        
        // Hardcoded URL should always be valid, but make it explicit
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            preconditionFailure("Invalid hardcoded Anthropic API URL. This is a programming error.")
        }
        self.baseURL = url
    }
    
    // MARK: - MCPClientProtocol Implementation
    
    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await generateText(prompt: prompt, systemMessage: nil, temperature: temperature, maxTokens: nil)
    }
    
    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?
    ) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: systemMessage,
            temperature: temperature, maxTokens: maxTokens,
            model: nil, timeout: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    func generateText(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        model: String?, timeout: TimeInterval?
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }
        
        let response = try await sendClaudeRequest(
            prompt: prompt,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens ?? 2048,
            model: model,
            timeout: timeout
        )
        
        return response
    }
    
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await generateStructuredJSON(prompt: prompt, systemMessage: nil, temperature: temperature, maxTokens: nil)
    }
    
    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?
    ) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: systemMessage,
            temperature: temperature, maxTokens: maxTokens,
            model: nil, timeout: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    func generateStructuredJSON(
        prompt: String, systemMessage: String?,
        temperature: Double, maxTokens: Int?,
        model: String?, timeout: TimeInterval?
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }
        
        // Enhance prompt to ensure JSON output
        // swiftlint:disable:next line_length
        let jsonInstruction = "IMPORTANT: Return ONLY valid JSON in your response. Do not include any markdown formatting, code blocks, or explanatory text. Just the raw JSON object."
        let enhancedPrompt = """
        \(prompt)

        \(jsonInstruction)
        """
        
        let response = try await sendClaudeRequest(
            prompt: enhancedPrompt,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens ?? 4096,
            model: model,
            timeout: timeout
        )
        
        // Clean up response if it contains markdown code blocks
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = cleanedResponse
                .replacingOccurrences(of: "```json\n", with: "")
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleanedResponse.hasPrefix("```") {
            cleanedResponse = cleanedResponse
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Validate it's proper JSON
        do {
            _ = try JSONSerialization.jsonObject(with: Data(cleanedResponse.utf8))
        } catch {
            throw AnthropicAPIError.invalidJSON(cleanedResponse)
        }
        
        return cleanedResponse
    }
    
    func analyzePatterns(text: String, context: String) async throws -> [String] {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }
        
        let prompt = """
        Analyze the following text and identify 3-5 key patterns.
        
        Context: \(context)
        
        Text to analyze:
        \(text)
        
        Return ONLY a JSON array of strings, like: ["Pattern 1", "Pattern 2", "Pattern 3"]
        """
        
        let response = try await sendClaudeRequest(
            prompt: prompt,
            temperature: 0.3,
            maxTokens: 1024
        )
        
        // Parse JSON array
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedResponse.hasPrefix("```") {
            cleanedResponse = cleanedResponse
                .replacingOccurrences(of: "```json\n", with: "")
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let data = Data(cleanedResponse.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }
    
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        // Not implemented for direct API - return empty results
        return []
    }
    
    // MARK: - Private Helpers

    private func sendClaudeRequest(
        prompt: String, systemMessage: String? = nil,
        temperature: Double, maxTokens: Int,
        model: String? = nil, timeout: TimeInterval? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }

        let resolvedModel = model ?? "claude-sonnet-4-20250514"
        let resolvedTimeout = timeout ?? 60

        Self.logger.debug(
            "Making request to \(self.baseURL, privacy: .public) with model \(resolvedModel, privacy: .public)"
        )
        Self.logger.debug(
            // swiftlint:disable:next line_length
            "API Key length: \(self.apiKey.count, privacy: .public), starts with: \(self.apiKey.prefix(7), privacy: .private)"
        )

        let messages: [[String: String]] = [["role": "user", "content": prompt]]
        let config = ClaudeRequestConfig(
            model: resolvedModel, maxTokens: maxTokens,
            temperature: temperature, timeout: resolvedTimeout
        )
        let request = try buildAPIRequest(messages: messages, systemMessage: systemMessage, config: config)

        do {
            Self.logger.debug("Sending request...")
            let (data, response) = try await session.data(for: request)
            Self.logger.debug("Received response")

            let httpResponse = try validateHTTPResponse(response, data: data)
            let (responseBody, text) = try parseResponseBody(data)

            trackAPIUsage(responseBody: responseBody, model: resolvedModel)
            _ = httpResponse // used for validation only
            return text
        } catch let error as AnthropicAPIError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    // MARK: - Multi-Turn Conversation

    /// Send a multi-turn conversation to the Anthropic API.
    func sendConversation(
        messages: [[String: String]],
        systemMessage: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        model: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }

        let resolvedModel = model ?? "claude-sonnet-4-20250514"
        let resolvedTimeout = timeout ?? 90

        Self.logger.debug(
            "Sending conversation with \(messages.count) messages using \(resolvedModel, privacy: .public)"
        )

        let config = ClaudeRequestConfig(
            model: resolvedModel, maxTokens: maxTokens,
            temperature: temperature, timeout: resolvedTimeout
        )
        let request = try buildAPIRequest(messages: messages, systemMessage: systemMessage, config: config)

        do {
            let (data, response) = try await session.data(for: request)
            _ = try validateHTTPResponse(response, data: data)
            let (_, text) = try parseResponseBody(data)
            return text
        } catch let error as AnthropicAPIError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    // MARK: - Request Building

    private struct ClaudeRequestConfig {
        let model: String
        let maxTokens: Int
        let temperature: Double
        let timeout: TimeInterval
        let stream: Bool

        init(model: String, maxTokens: Int, temperature: Double, timeout: TimeInterval, stream: Bool = false) {
            self.model = model; self.maxTokens = maxTokens; self.temperature = temperature
            self.timeout = timeout; self.stream = stream
        }
    }

    private func buildAPIRequest(
        messages: Any, systemMessage: String?, config: ClaudeRequestConfig
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = config.timeout

        var requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "messages": messages
        ]
        if let systemMessage, !systemMessage.isEmpty {
            requestBody["system"] = systemMessage
        }
        if config.stream { requestBody["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }

    // MARK: - Response Handling

    @discardableResult
    private func validateHTTPResponse(
        _ response: URLResponse, data: Data
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw buildHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        return httpResponse
    }

    private func buildHTTPError(statusCode: Int, data: Data) -> AnthropicAPIError {
        let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        Self.logger.debug("HTTP Status Code: \(statusCode, privacy: .public)")

        guard let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = errorBody["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return .apiError(statusCode: statusCode, message: "Unknown error. Response: \(responseString)")
        }

        let helpfulMessage: String
        switch statusCode {
        case 401:
            helpfulMessage = "Invalid API key. Please check your API key in Settings. \(message)"
        case 429:
            helpfulMessage = "Rate limit exceeded. Please wait a moment and try again. \(message)"
        case 529:
            helpfulMessage = "Claude API is temporarily overloaded. " +
                "Please try again in a few moments. \(message)"
        default:
            helpfulMessage = message
        }
        return .apiError(statusCode: statusCode, message: helpfulMessage)
    }

    private func parseResponseBody(_ data: Data) throws -> ([String: Any], String) {
        let responseBody: [String: Any]
        do {
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AnthropicAPIError.invalidResponse
            }
            responseBody = body
        } catch {
            throw AnthropicAPIError.invalidResponse
        }
        guard let content = responseBody["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AnthropicAPIError.invalidResponseFormat
        }
        return (responseBody, text)
    }

    private func trackAPIUsage(responseBody: [String: Any], model: String) {
        let usage = responseBody["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int
        let outputTokens = usage?["output_tokens"] as? Int
        Task { @MainActor in
            APIUsageTracker.shared.logUsage(
                model: model, inputTokens: inputTokens, outputTokens: outputTokens
            )
        }
    }

    private func mapNetworkError(_ error: Error) -> AnthropicAPIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .apiError(statusCode: 0, message: "No internet connection. Please check your network settings.")
            case .cannotFindHost, .cannotConnectToHost:
                Self.logger.debug(
                    // swiftlint:disable:next line_length
                    "URLError: \(urlError.code.rawValue, privacy: .public) - \(urlError.localizedDescription, privacy: .public)"
                )
                return .apiError(
                    statusCode: 0,
                    message: "Cannot reach api.anthropic.com. Check your internet connection or firewall settings."
                )
            case .timedOut:
                return .apiError(statusCode: 0, message: "Request timed out. Please try again.")
            case .secureConnectionFailed:
                return .apiError(statusCode: 0,
                                message: "Secure connection failed. Check your system date/time settings.")
            default:
                return .apiError(statusCode: 0, message: "Network error: \(urlError.localizedDescription)")
            }
        }
        Self.logger.debug("Unknown error: \(error.localizedDescription)")
        return .apiError(statusCode: 0, message: "Network error: \(error.localizedDescription)")
    }
    
    // MARK: - Streaming Conversation

    /// Send a multi-turn conversation with streaming, calling onDelta for each text chunk.
    /// Returns the full response text when complete.
    func streamConversation(
        messages: [[String: String]],
        systemMessage: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        model: String? = nil,
        timeout: TimeInterval? = nil,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }

        let resolvedModel = model ?? "claude-sonnet-4-20250514"
        let resolvedTimeout = timeout ?? 120

        Self.logger.debug(
            "Streaming conversation with \(messages.count) messages using \(resolvedModel, privacy: .public)"
        )

        let config = ClaudeRequestConfig(
            model: resolvedModel, maxTokens: maxTokens,
            temperature: temperature, timeout: resolvedTimeout, stream: true
        )
        let request = try buildAPIRequest(messages: messages, systemMessage: systemMessage, config: config)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            throw buildHTTPError(statusCode: httpResponse.statusCode, data: errorData)
        }

        return try await parseSSEStream(bytes: bytes, onDelta: onDelta)
    }

    private func parseSSEStream(
        bytes: URLSession.AsyncBytes, onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            if jsonString == "[DONE]" { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let eventType = event["type"] as? String
            if eventType == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullText += text
                onDelta(text)
            }
            if eventType == "error",
               let error = event["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AnthropicAPIError.apiError(statusCode: 0, message: message)
            }
        }
        return fullText
    }

    // MARK: - API Key Management
    
    private static func loadAPIKey() -> String {
        // Try UserDefaults first (easiest for users to configure)
        if let key = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !key.isEmpty {
            return key
        }
        
        // Could add keychain support here in the future
        
        return ""
    }
    
    /// Save API key to UserDefaults
    static func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "anthropicAPIKey")
    }
    
    /// Check if API key is configured
    static func hasAPIKey() -> Bool {
        let key = loadAPIKey()
        // Modern Anthropic API keys should start with sk-ant-api03-
        return !key.isEmpty && (key.hasPrefix("sk-ant-api03-") || key.hasPrefix("sk-ant-"))
    }
    
    /// Clear saved API key
    static func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
    }
}
// swiftlint:enable type_body_length

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
