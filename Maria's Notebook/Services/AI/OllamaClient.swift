//
//  OllamaClient.swift
//  Maria's Notebook
//
//  HTTP client for Ollama local LLM server.
//  Connects to localhost:11434 (configurable) for local model inference.
//

import Foundation
import OSLog

/// MCPClientProtocol implementation backed by a local Ollama server.
/// Ollama must be running separately on the user's machine.
final class OllamaClient: MCPClientProtocol {
    private static let logger = Logger.ai

    private let session: URLSession
    private var baseURL: URL

    /// The model to use for inference (e.g., "llama3.2", "phi4", "mistral").
    var modelName: String

    init(
        baseURL: URL? = nil,
        modelName: String = "llama3.2",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? URL(string: "http://localhost:11434")!
        self.modelName = modelName
        self.session = session
    }

    // MARK: - Availability

    /// Checks if Ollama is running and reachable.
    var isAvailable: Bool {
        get async {
            do {
                _ = try await listModels()
                return true
            } catch {
                return false
            }
        }
    }

    /// Lists models available on the Ollama server.
    func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.serverUnreachable
        }

        let result = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return result.models
    }

    // MARK: - MCPClientProtocol

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await generateText(prompt: prompt, systemMessage: nil, temperature: temperature, maxTokens: nil, model: nil, timeout: nil)
    }

    func generateText(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")

        var body: [String: Any] = [
            "model": model ?? modelName,
            "prompt": prompt,
            "stream": false,
            "options": buildOptions(temperature: temperature, maxTokens: maxTokens)
        ]
        if let systemMessage, !systemMessage.isEmpty {
            body["system"] = systemMessage
        }

        let data = try await postJSON(url: url, body: body, timeout: timeout ?? 120)
        let result = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return result.response
    }

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await generateStructuredJSON(prompt: prompt, systemMessage: nil, temperature: temperature, maxTokens: nil, model: nil, timeout: nil)
    }

    func generateStructuredJSON(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        let enhancedPrompt = """
        \(prompt)

        IMPORTANT: Return ONLY valid JSON in your response. No markdown formatting, no code blocks, no explanatory text. Just the raw JSON object.
        """

        let text = try await generateText(
            prompt: enhancedPrompt,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            model: model,
            timeout: timeout
        )

        // Clean up markdown code blocks if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json\n", with: "")
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Validate JSON
        do {
            _ = try JSONSerialization.jsonObject(with: Data(cleaned.utf8))
        } catch {
            throw OllamaError.invalidJSON(cleaned)
        }

        return cleaned
    }

    func analyzePatterns(text: String, context: String) async throws -> [String] {
        let prompt = """
        Analyze the following text and identify 3-5 key patterns.
        Context: \(context)
        Text: \(text)
        Return ONLY a JSON array of strings, like: ["Pattern 1", "Pattern 2"]
        """
        let json = try await generateStructuredJSON(prompt: prompt, temperature: 0.3)
        return try JSONDecoder().decode([String].self, from: Data(json.utf8))
    }

    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        [] // Local model has no external knowledge base
    }

    // MARK: - Multi-Turn Conversation

    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")

        // Convert to Ollama chat format
        var ollamaMessages: [[String: String]] = []
        if let systemMessage, !systemMessage.isEmpty {
            ollamaMessages.append(["role": "system", "content": systemMessage])
        }
        for msg in messages {
            ollamaMessages.append([
                "role": msg["role"] ?? "user",
                "content": msg["content"] ?? ""
            ])
        }

        let body: [String: Any] = [
            "model": model ?? modelName,
            "messages": ollamaMessages,
            "stream": false,
            "options": buildOptions(temperature: temperature, maxTokens: maxTokens)
        ]

        let data = try await postJSON(url: url, body: body, timeout: timeout ?? 120)
        let result = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return result.message.content
    }

    // MARK: - Streaming Conversation

    func streamConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")

        var ollamaMessages: [[String: String]] = []
        if let systemMessage, !systemMessage.isEmpty {
            ollamaMessages.append(["role": "system", "content": systemMessage])
        }
        for msg in messages {
            ollamaMessages.append([
                "role": msg["role"] ?? "user",
                "content": msg["content"] ?? ""
            ])
        }

        let body: [String: Any] = [
            "model": model ?? modelName,
            "messages": ollamaMessages,
            "stream": true,
            "options": buildOptions(temperature: temperature, maxTokens: maxTokens)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout ?? 120

        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Ollama streams newline-delimited JSON objects
        var fullText = ""
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OllamaChatStreamChunk.self, from: lineData) else {
                continue
            }

            let text = chunk.message.content
            if !text.isEmpty {
                fullText += text
                onDelta(text)
            }

            if chunk.done { break }
        }

        return fullText
    }

    // MARK: - Private Helpers

    private func buildOptions(temperature: Double, maxTokens: Int?) -> [String: Any] {
        var options: [String: Any] = ["temperature": temperature]
        if let maxTokens {
            options["num_predict"] = maxTokens
        }
        return options
    }

    private func postJSON(url: URL, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }

            guard http.statusCode == 200 else {
                let responseString = String(data: data, encoding: .utf8) ?? ""
                throw OllamaError.serverError(statusCode: http.statusCode, detail: responseString)
            }

            return data
        } catch let error as OllamaError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                throw OllamaError.serverUnreachable
            case .timedOut:
                throw OllamaError.timeout
            default:
                throw OllamaError.networkError(urlError.localizedDescription)
            }
        }
    }

    // MARK: - Configuration

    /// Updates the base URL (e.g., user changed it in settings).
    func updateBaseURL(_ url: URL) {
        baseURL = url
    }
}

// MARK: - Ollama API Types

struct OllamaModel: Codable, Identifiable {
    let name: String
    let size: Int64
    let digest: String
    let modifiedAt: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case modifiedAt = "modified_at"
    }
}

private struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

private struct OllamaGenerateResponse: Codable {
    let response: String
}

private struct OllamaChatResponse: Codable {
    let message: OllamaChatMessage
}

private struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaChatStreamChunk: Codable {
    let message: OllamaChatMessage
    let done: Bool
}

// MARK: - Errors

enum OllamaError: Error, LocalizedError {
    case serverUnreachable
    case serverError(statusCode: Int, detail: String = "")
    case invalidResponse
    case invalidJSON(String)
    case timeout
    case networkError(String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Cannot connect to Ollama. Make sure Ollama is running (ollama serve)."
        case .serverError(let code, let detail):
            return "Ollama server error (\(code))\(detail.isEmpty ? "" : ": \(detail)")"
        case .invalidResponse:
            return "Invalid response from Ollama server."
        case .invalidJSON(let text):
            return "Ollama returned invalid JSON: \(text.prefix(100))..."
        case .timeout:
            return "Ollama request timed out. The model may be loading — try again."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .modelNotFound(let name):
            return "Model '\(name)' not found. Run: ollama pull \(name)"
        }
    }
}
