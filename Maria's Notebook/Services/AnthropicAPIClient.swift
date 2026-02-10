//
//  AnthropicAPIClient.swift
//  Maria's Notebook
//
//  Direct Anthropic API client for student analysis
//

import Foundation

/// Direct implementation that connects to Anthropic's Claude API
final class AnthropicAPIClient: MCPClientProtocol {
    
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
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }
        
        let response = try await sendClaudeRequest(
            prompt: prompt,
            temperature: temperature,
            maxTokens: 2048
        )
        
        return response
    }
    
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }
        
        // Enhance prompt to ensure JSON output
        let enhancedPrompt = """
        \(prompt)
        
        IMPORTANT: Return ONLY valid JSON in your response. Do not include any markdown formatting, code blocks, or explanatory text. Just the raw JSON object.
        """
        
        let response = try await sendClaudeRequest(
            prompt: enhancedPrompt,
            temperature: temperature,
            maxTokens: 4096
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
    
    private func sendClaudeRequest(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        // Double-check API key
        guard !apiKey.isEmpty else {
            throw AnthropicAPIError.noAPIKey
        }
        
        print("🔧 AnthropicAPIClient: Making request to \(baseURL)")
        print("🔧 API Key length: \(apiKey.count), starts with: \(apiKey.prefix(7))")
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let requestBody: [String: Any] = [
            "model": "claude-3-5-sonnet-20250122",
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            print("🔧 Sending request...")
            let (data, response) = try await session.data(for: request)
            print("🔧 Received response")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AnthropicAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                // Try to parse error message
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                print("🔧 Error response body: \(responseString)")
                
                if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorBody["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("🔧 Parsed error message: \(message)")
                    throw AnthropicAPIError.apiError(statusCode: httpResponse.statusCode, message: message)
                }
                throw AnthropicAPIError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error. Response: \(responseString)")
            }
            
            // Parse response
            guard let responseBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = responseBody["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw AnthropicAPIError.invalidResponseFormat
            }
            
            return text
        } catch let error as AnthropicAPIError {
            throw error
        } catch let urlError as URLError {
            // Provide more specific error messages for common network issues
            switch urlError.code {
            case .notConnectedToInternet:
                throw AnthropicAPIError.apiError(statusCode: 0, message: "No internet connection. Please check your network settings.")
            case .cannotFindHost, .cannotConnectToHost:
                print("🔧 URLError: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
                throw AnthropicAPIError.apiError(statusCode: 0, message: "Cannot reach api.anthropic.com. Check your internet connection or firewall settings.")
            case .timedOut:
                throw AnthropicAPIError.apiError(statusCode: 0, message: "Request timed out. Please try again.")
            case .secureConnectionFailed:
                throw AnthropicAPIError.apiError(statusCode: 0, message: "Secure connection failed. Check your system date/time settings.")
            default:
                print("🔧 URLError code: \(urlError.code.rawValue)")
                print("🔧 URLError: \(urlError)")
                throw AnthropicAPIError.apiError(statusCode: 0, message: "Network error: \(urlError.localizedDescription)")
            }
        } catch {
            print("🔧 Unknown error: \(error)")
            throw AnthropicAPIError.apiError(statusCode: 0, message: "Network error: \(error.localizedDescription)")
        }
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
        return !key.isEmpty && key.hasPrefix("sk-ant-")
    }
    
    /// Clear saved API key
    static func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
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
