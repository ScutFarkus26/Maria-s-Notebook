//
//  AIClientRouter.swift
//  Maria's Notebook
//
//  Routes AI requests to the appropriate provider based on per-feature model selection.
//  Supports: Apple Intelligence, MLX Swift, Ollama, and Claude API.
//  Implements MCPClientProtocol so it can be injected anywhere the protocol is used.
//

import Foundation
import OSLog

/// Routes AI requests based on the user's per-feature model selection.
///
/// Supports three routing strategies:
/// - **Direct**: Route to a specific provider (Claude, Apple Intelligence, MLX, Ollama)
/// - **Local First (Auto)**: Cascade through local providers, fall back to Claude
///
/// Usage:
/// ```swift
/// let router = AIClientRouter()
/// router.activeFeatureArea = .chat
/// let response = try await router.generateText(prompt: "Hello", temperature: 0.7)
/// ```
final class AIClientRouter: MCPClientProtocol {
    private static let logger = Logger.ai

    // MARK: - Provider Clients

    let anthropicClient: AnthropicAPIClient
    let ollamaClient: OllamaClient

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private var _localClient: LocalModelClient?

    @available(macOS 26.0, iOS 26.0, *)
    var localClient: LocalModelClient {
        if let c = _localClient { return c }
        let c = LocalModelClient()
        _localClient = c
        return c
    }
    #endif

    #if ENABLE_MLX_MODELS && canImport(MLXLLM)
    private var _mlxClient: MLXModelClient?
    var mlxClient: MLXModelClient {
        if let c = _mlxClient { return c }
        let c = MLXModelClient(modelManager: mlxModelManager)
        _mlxClient = c
        return c
    }
    let mlxModelManager: MLXModelManager
    #else
    let mlxModelManager: MLXModelManager
    #endif

    /// The feature area currently being served (determines routing).
    /// Set before each call by the calling service via `configureForFeature(_:)`.
    var activeFeatureArea: AIFeatureArea = .chat

    init(
        anthropicClient: AnthropicAPIClient = AnthropicAPIClient(),
        ollamaClient: OllamaClient = OllamaClient()
    ) {
        self.anthropicClient = anthropicClient
        self.ollamaClient = ollamaClient
        self.mlxModelManager = MLXModelManager()

    }

    // MARK: - Routing

    private enum Route {
        case claude(String)        // model ID
        case appleOnDevice
        case mlxLocal
        case ollamaLocal
        case localFirstAuto        // cascade
    }

    private func resolveRoute() -> Route {
        let model = activeFeatureArea.resolvedModel()
        switch model {
        case .claudeSonnet, .claudeHaiku, .claudeOpus:
            return .claude(model.rawValue)
        case .appleOnDevice:
            return .appleOnDevice
        case .mlxLocal:
            return .mlxLocal
        case .ollamaLocal:
            return .ollamaLocal
        case .localFirstAuto:
            return .localFirstAuto
        }
    }

    // MARK: - MCPClientProtocol — generateText

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
        try await route { client in
            try await client.generateText(prompt: prompt, systemMessage: systemMessage, temperature: temperature, maxTokens: maxTokens, model: model, timeout: timeout)
        }
    }

    // MARK: - MCPClientProtocol — generateStructuredJSON

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
        try await route { client in
            try await client.generateStructuredJSON(prompt: prompt, systemMessage: systemMessage, temperature: temperature, maxTokens: maxTokens, model: model, timeout: timeout)
        }
    }

    // MARK: - MCPClientProtocol — analyzePatterns

    func analyzePatterns(text: String, context: String) async throws -> [String] {
        try await route { client in
            try await client.analyzePatterns(text: text, context: context)
        }
    }

    // MARK: - MCPClientProtocol — searchKnowledgeBase

    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        // Always use Claude for knowledge base (local models have none)
        try await anthropicClient.searchKnowledgeBase(query: query, domain: domain)
    }

    // MARK: - MCPClientProtocol — sendConversation

    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await route { client in
            try await client.sendConversation(messages: messages, systemMessage: systemMessage, temperature: temperature, maxTokens: maxTokens, model: model, timeout: timeout)
        }
    }

    // MARK: - MCPClientProtocol — streamConversation

    func streamConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await route { client in
            try await client.streamConversation(messages: messages, systemMessage: systemMessage, temperature: temperature, maxTokens: maxTokens, model: model, timeout: timeout, onDelta: onDelta)
        }
    }

    // MARK: - Routing Engine

    /// Routes a request to the appropriate provider based on the current feature area's model setting.
    private func route<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        switch resolveRoute() {
        case .claude(let modelID):
            Self.logger.debug("Routing to Claude (\(modelID)) for \(self.activeFeatureArea.rawValue)")
            return try await work(anthropicClient)

        case .appleOnDevice:
            return try await callAppleIntelligence(work)

        case .mlxLocal:
            return try await callMLX(work)

        case .ollamaLocal:
            Self.logger.debug("Routing to Ollama for \(self.activeFeatureArea.rawValue)")
            return try await work(ollamaClient)

        case .localFirstAuto:
            return try await localFirstCascade(work)
        }
    }

    /// Tries local providers in order, falls back to Claude.
    private func localFirstCascade<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        // 1. Apple Intelligence
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            if localClient.isAvailable {
                do {
                    Self.logger.debug("Local-first: trying Apple Intelligence for \(self.activeFeatureArea.rawValue)")
                    return try await work(localClient)
                } catch let error as LocalModelError {
                    Self.logger.info("Apple Intelligence failed (\(error.localizedDescription)), trying next provider")
                }
            }
        }
        #endif

        // 2. MLX Swift
        #if ENABLE_MLX_MODELS && canImport(MLXLLM)
        if mlxClient.isAvailable {
            do {
                Self.logger.debug("Local-first: trying MLX for \(self.activeFeatureArea.rawValue)")
                return try await work(mlxClient)
            } catch let error as MLXModelError {
                Self.logger.info("MLX failed (\(error.localizedDescription)), trying next provider")
            }
        }
        #endif

        // 3. Ollama
        if await ollamaClient.isAvailable {
            do {
                Self.logger.debug("Local-first: trying Ollama for \(self.activeFeatureArea.rawValue)")
                return try await work(ollamaClient)
            } catch let error as OllamaError {
                Self.logger.info("Ollama failed (\(error.localizedDescription)), falling back to Claude")
            }
        }

        // 4. Claude (final fallback)
        Self.logger.debug("Local-first: all local providers unavailable, routing to Claude for \(self.activeFeatureArea.rawValue)")
        return try await work(anthropicClient)
    }

    // MARK: - Provider Helpers

    private func callAppleIntelligence<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            Self.logger.debug("Routing to Apple Intelligence for \(self.activeFeatureArea.rawValue)")
            return try await work(localClient)
        }
        #endif
        throw LocalModelError.unavailable("Apple Intelligence is not available in this build.")
    }

    private func callMLX<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_MLX_MODELS && canImport(MLXLLM)
        Self.logger.debug("Routing to MLX for \(self.activeFeatureArea.rawValue)")
        return try await work(mlxClient)
        #else
        throw MLXModelError.noModelLoaded
        #endif
    }
}

// MARK: - Protocol Extension for Feature Configuration

extension MCPClientProtocol {
    /// Sets the active feature area on the router if the client is a router.
    /// Safe no-op for non-router clients (e.g., MockMCPClient in tests).
    func configureForFeature(_ area: AIFeatureArea) {
        (self as? AIClientRouter)?.activeFeatureArea = area
    }
}
