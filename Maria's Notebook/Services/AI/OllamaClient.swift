//
//  OllamaClient.swift
//  Maria's Notebook
//
//  HTTP client for Ollama local LLM server.
//  Connects to localhost:11434 (configurable) for local model inference.
//

import Foundation
import OSLog

// MCPClientProtocol implementation backed by a local Ollama server.
// Ollama must be running separately on the user's machine.
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

    // MARK: - Model Pull

    /// Pulls (downloads/installs) a model from the Ollama registry.
    /// Returns an `AsyncThrowingStream` of progress updates that the caller iterates.
    /// This avoids `@Sendable` callback issues — the caller reads progress on their own actor.
    ///
    /// - Parameter name: The model identifier (e.g., "llama3.2", "mistral").
    /// - Returns: A stream of `OllamaPullProgress` values, ending on success or throwing on failure.
    func pullModel(name: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [baseURL, session] in
                do {
                    let request = try OllamaClient.buildPullRequest(for: name, baseURL: baseURL)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OllamaError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        throw OllamaError.serverError(statusCode: http.statusCode)
                    }
                    try await OllamaClient.streamPullProgress(for: name, bytes: bytes, into: continuation)
                } catch let error as OllamaError {
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    continuation.finish(throwing: OllamaError.from(urlError))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        let enhancedPrompt = """
        \(prompt)

        IMPORTANT: Return ONLY valid JSON in your response. No markdown formatting, \
        no code blocks, no explanatory text. Just the raw JSON object.
        """

        let text = try await generateText(
            prompt: enhancedPrompt,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            model: model,
            timeout: timeout
        )

        let cleaned = Self.stripMarkdownCodeBlock(text)

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

    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")

        let body: [String: Any] = [
            "model": model ?? modelName,
            "messages": Self.buildChatMessages(messages, systemMessage: systemMessage),
            "stream": false,
            "options": buildOptions(temperature: temperature, maxTokens: maxTokens)
        ]

        let data = try await postJSON(url: url, body: body, timeout: timeout ?? 120)
        let result = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return result.message.content
    }

    // MARK: - Streaming Conversation

    // swiftlint:disable:next function_parameter_count
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

        let body: [String: Any] = [
            "model": model ?? modelName,
            "messages": Self.buildChatMessages(messages, systemMessage: systemMessage),
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

    // MARK: - Configuration

    /// Updates the base URL (e.g., user changed it in settings).
    func updateBaseURL(_ url: URL) {
        baseURL = url
    }
}

// MARK: - Private Helpers

extension OllamaClient {

    /// Converts user-supplied messages into the Ollama chat format,
    /// prepending a system message if provided.
    static func buildChatMessages(
        _ messages: [[String: String]],
        systemMessage: String?
    ) -> [[String: String]] {
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
        return ollamaMessages
    }

    /// Strips markdown code-block fencing (```json ... ``` or ``` ... ```) from LLM output.
    static func stripMarkdownCodeBlock(_ text: String) -> String {
        var cleaned = text.trimmed()
        if cleaned.hasPrefix("```json") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json\n", with: "")
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmed()
        } else if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```", with: "")
                .trimmed()
        }
        return cleaned
    }

    func buildOptions(temperature: Double, maxTokens: Int?) -> [String: Any] {
        var options: [String: Any] = ["temperature": temperature]
        if let maxTokens {
            options["num_predict"] = maxTokens
        }
        return options
    }

    func postJSON(url: URL, body: [String: Any], timeout: TimeInterval) async throws -> Data {
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
            throw OllamaError.from(urlError)
        }
    }

    static func buildPullRequest(for name: String, baseURL: URL) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("api/pull")
        let body: [String: Any] = ["name": name, "stream": true]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 3600
        Self.logger.info("Pulling model: \(name)")
        return request
    }

    static func streamPullProgress(
        for name: String,
        bytes: URLSession.AsyncBytes,
        into continuation: AsyncThrowingStream<OllamaPullProgress, Error>.Continuation
    ) async throws {
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OllamaPullChunk.self, from: lineData)
            else { continue }
            continuation.yield(OllamaPullProgress(
                status: chunk.status, completed: chunk.completed, total: chunk.total
            ))
            if chunk.status == "success" {
                Self.logger.info("Successfully pulled model: \(name)")
                continuation.finish()
                return
            }
        }
        continuation.finish(throwing: OllamaError.pullFailed(name))
    }
}
