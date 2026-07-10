//
//  AIClientRouter.swift
//  Maria's Notebook
//
//  Routes AI requests to the appropriate provider based on per-feature model selection.
//  Supports Apple Intelligence by default, with Claude available only when explicitly selected.
//  Implements MCPClientProtocol so it can be injected anywhere the protocol is used.
//

import Foundation
import OSLog

/// Routes AI requests based on the user's per-feature model selection.
///
/// Supports two routing strategies:
/// - **Direct**: Route to a specific provider (Claude, Apple on-device, Apple Private Cloud)
/// - **Apple Intelligence (Auto)**: On-device first, then Private Cloud Compute
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

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    private var _localClient: LocalModelClient?

    /// Apple's on-device model (Apple Intelligence).
    var localClient: LocalModelClient {
        if let c = _localClient { return c }
        let c = LocalModelClient()
        _localClient = c
        return c
    }

    private var _privateCloudClient: PrivateCloudModelClient?

    /// Apple's server-side model on Private Cloud Compute.
    var privateCloudClient: PrivateCloudModelClient {
        if let c = _privateCloudClient { return c }
        let c = PrivateCloudModelClient()
        _privateCloudClient = c
        return c
    }
    #endif

    /// The feature area currently being served (determines routing).
    /// Set before each call by the calling service via `configureForFeature(_:)`.
    var activeFeatureArea: AIFeatureArea = .chat

    init(anthropicClient: AnthropicAPIClient = AnthropicAPIClient()) {
        self.anthropicClient = anthropicClient
    }

    // MARK: - Routing

    private enum Route {
        case claude(String)        // model ID
        case appleOnDevice
        case applePrivateCloud
        case localFirstAuto        // cascade
    }

    private func resolveRoute() -> Route {
        let model = activeFeatureArea.resolvedModel()
        switch model {
        case .claudeSonnet, .claudeHaiku:
            return .claude(model.rawValue)
        case .appleOnDevice:
            return .appleOnDevice
        case .applePrivateCloud:
            return .applePrivateCloud
        case .localFirstAuto:
            return .localFirstAuto
        }
    }

    // MARK: - MCPClientProtocol — generateText

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: nil,
            temperature: temperature, maxTokens: nil,
            model: nil, timeout: nil
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
        try await route { client in
            try await client.generateText(
                prompt: prompt, systemMessage: systemMessage,
                temperature: temperature, maxTokens: maxTokens,
                model: model, timeout: timeout
            )
        }
    }

    // MARK: - MCPClientProtocol — generateStructuredJSON

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: nil,
            temperature: temperature, maxTokens: nil,
            model: nil, timeout: nil
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
        try await route { client in
            try await client.generateStructuredJSON(
                prompt: prompt, systemMessage: systemMessage,
                temperature: temperature, maxTokens: maxTokens,
                model: model, timeout: timeout
            )
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
        try await route { client in
            try await client.searchKnowledgeBase(query: query, domain: domain)
        }
    }

    // MARK: - MCPClientProtocol — sendConversation

    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        model: String?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await route { client in
            try await client.sendConversation(
                messages: messages,
                systemMessage: systemMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                model: model, timeout: timeout
            )
        }
    }

    // MARK: - MCPClientProtocol — streamConversation

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
        try await route { client in
            try await client.streamConversation(
                messages: messages,
                systemMessage: systemMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                model: model, timeout: timeout,
                onDelta: onDelta
            )
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

        case .applePrivateCloud:
            return try await callApplePrivateCloud(work)

        case .localFirstAuto:
            return try await localFirstCascade(work)
        }
    }

    /// Tries Apple's models in order: on-device, then Private Cloud Compute.
    /// Claude is never a hidden fallback; it is used only when explicitly selected.
    private func localFirstCascade<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        var failures: [String] = []

        // 1. Apple Intelligence on-device (fastest, fully private, free)
        if localClient.isAvailable {
            do {
                Self.logger.debug("Apple-first: trying on-device for \(self.activeFeatureArea.rawValue)")
                return try await work(localClient)
            } catch {
                Self.logger.info("On-device failed (\(error.localizedDescription)), trying next provider")
                failures.append(error.localizedDescription)
            }
        } else {
            failures.append(localClient.unavailabilityReason)
        }

        // 2. Private Cloud Compute (larger context, still private, no API key)
        if privateCloudClient.isAvailable {
            do {
                Self.logger.debug("Apple-first: trying Private Cloud Compute for \(self.activeFeatureArea.rawValue)")
                return try await work(privateCloudClient)
            } catch {
                Self.logger.info("Private Cloud Compute failed (\(error.localizedDescription))")
                failures.append(error.localizedDescription)
            }
        } else {
            failures.append(privateCloudClient.unavailabilityReason)
        }

        let reason = failures.filter { !$0.isEmpty }.joined(separator: " ")
        throw LocalModelError.unavailable(
            reason.isEmpty ? "Apple Intelligence is not available right now." : reason
        )
        #else
        throw LocalModelError.unavailable("Apple Intelligence is not available in this build.")
        #endif
    }

    // MARK: - Provider Helpers

    private func callAppleIntelligence<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        Self.logger.debug("Routing to Apple Intelligence for \(self.activeFeatureArea.rawValue)")
        return try await work(localClient)
        #else
        throw LocalModelError.unavailable("Apple Intelligence is not available in this build.")
        #endif
    }

    private func callApplePrivateCloud<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        Self.logger.debug("Routing to Private Cloud Compute for \(self.activeFeatureArea.rawValue)")
        return try await work(privateCloudClient)
        #else
        throw LocalModelError.unavailable("Private Cloud Compute is not available in this build.")
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
