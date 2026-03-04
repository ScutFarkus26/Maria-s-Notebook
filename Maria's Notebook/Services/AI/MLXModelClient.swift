//
//  MLXModelClient.swift
//  Maria's Notebook
//
//  MCPClientProtocol implementation backed by MLX Swift for local model inference.
//  Requires a model to be downloaded and loaded via MLXModelManager.
//  Guarded behind ENABLE_MLX_MODELS flag.
//

import Foundation
import OSLog

#if ENABLE_MLX_MODELS && canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon

/// On-device AI client using MLX Swift for Apple Silicon inference.
@MainActor
final class MLXModelClient: MCPClientProtocol {
    private static let logger = Logger.ai

    private let modelManager: MLXModelManager

    init(modelManager: MLXModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Availability

    /// Whether a model is loaded and ready for inference.
    var isAvailable: Bool {
        modelManager.isReady
    }

    var unavailabilityReason: String {
        if !modelManager.isReady {
            return "No MLX model loaded. Download and load a model in Settings."
        }
        return ""
    }

    // MARK: - MCPClientProtocol

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: nil, temperature: temperature,
            maxTokens: nil, model: nil, timeout: nil
        )
    }

    func generateText(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        guard let container = modelManager.loadedModelContainer else {
            throw MLXModelError.noModelLoaded
        }

        let systemMsg = systemMessage ?? AIPrompts.generalAssistant
        let chatPrompt = buildChatPrompt(system: systemMsg, user: prompt)

        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: .init(prompt: chatPrompt))
            var output = ""
            let maxTokenCount = maxTokens ?? 2048

            for try await token in try context.model.generate(input: input, parameters: .init(temperature: Float(temperature))) {
                output += context.tokenizer.decode(token: token)
                if output.count > maxTokenCount * 4 { break } // Rough character limit
            }
            return output
        }

        return result
    }

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: nil, temperature: temperature,
            maxTokens: nil, model: nil, timeout: nil
        )
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

        IMPORTANT: Return ONLY valid JSON. No markdown, no code blocks, no explanatory text.
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
            throw MLXModelError.invalidJSON(cleaned)
        }

        return cleaned
    }

    func analyzePatterns(text: String, context: String) async throws -> [String] {
        let prompt = """
        Analyze the following text and identify 3-5 key patterns.
        Context: \(context)
        Text: \(text)
        Return ONLY a JSON array of strings.
        """
        let json = try await generateStructuredJSON(prompt: prompt, temperature: 0.3)
        return try JSONDecoder().decode([String].self, from: Data(json.utf8))
    }

    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        [] // Local model has no external knowledge base
    }

    // MARK: - Streaming

    func streamConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let container = modelManager.loadedModelContainer else {
            throw MLXModelError.noModelLoaded
        }

        let systemMsg = systemMessage ?? AIPrompts.generalAssistant

        // Flatten messages into chat format
        var chatText = "System: \(systemMsg)\n\n"
        for msg in messages {
            let role = msg["role"] ?? "user"
            let content = msg["content"] ?? ""
            chatText += "\(role.capitalized): \(content)\n\n"
        }
        chatText += "Assistant: "

        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: .init(prompt: chatText))
            var output = ""

            for try await token in try context.model.generate(input: input, parameters: .init(temperature: Float(temperature))) {
                let text = context.tokenizer.decode(token: token)
                output += text
                onDelta(text)
                if output.count > maxTokens * 4 { break }
            }
            return output
        }

        return result
    }

    // MARK: - Private

    private func buildChatPrompt(system: String, user: String) -> String {
        """
        System: \(system)

        User: \(user)

        Assistant:\(" ")
        """
    }
}

// MARK: - Errors

enum MLXModelError: Error, LocalizedError {
    case noModelLoaded
    case invalidJSON(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No MLX model loaded. Download and load a model in Settings → AI Models."
        case .invalidJSON(let text):
            return "MLX model returned invalid JSON: \(text.prefix(100))..."
        case .generationFailed(let msg):
            return "MLX generation failed: \(msg)"
        }
    }
}

#else

// MARK: - Stub when MLX is unavailable

enum MLXModelError: Error, LocalizedError {
    case noModelLoaded
    case invalidJSON(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "MLX models are not available in this build."
        case .invalidJSON(let text):
            return "Invalid JSON: \(text.prefix(100))..."
        case .generationFailed(let msg):
            return "Generation failed: \(msg)"
        }
    }
}

#endif
