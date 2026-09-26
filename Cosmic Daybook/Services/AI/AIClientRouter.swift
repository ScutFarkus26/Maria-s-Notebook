//
//  AIClientRouter.swift
//  Cosmic Daybook
//
//  Sends every in-app AI request to Apple Intelligence: the on-device model
//  first, then Private Cloud Compute when the guide allows it in Settings → AI.
//  Implements MCPClientProtocol so it can be injected anywhere the protocol is used.
//

import Foundation
import OSLog

/// Routes every request on-device first, then to Private Cloud Compute when
/// `automaticPrivateCloudAllowed`. The app has no other AI provider; Claude is
/// reached only from outside, over the MCP server.
final class AIClientRouter: MCPClientProtocol {
    private static let logger = Logger.ai

    // MARK: - Provider Clients

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

    /// Whether a request could be served right now: the on-device model is
    /// ready, or Private Cloud Compute is allowed and ready.
    static var isAvailable: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        LocalModelClient().isAvailable
            || (automaticPrivateCloudAllowed && PrivateCloudModelClient().isAvailable)
        #else
        false
        #endif
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
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        try await route { client in
            try await client.streamConversation(
                messages: messages,
                systemMessage: systemMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                model: model, timeout: timeout,
                onText: onText
            )
        }
    }

    func consumeEvidenceSources() async -> [EvidenceReference] {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        return await localClient.consumeEvidenceSources()
        #else
        return []
        #endif
    }

    // MARK: - Routing Engine

    /// Tries Apple's models in order: on-device, then Private Cloud Compute.
    private func route<T>(_ work: (MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        var failures: [String] = []

        // 1. Apple Intelligence on-device (fastest, fully private, free)
        if localClient.isAvailable {
            do {
                Self.logger.debug("Apple-first: trying on-device")
                return try await work(localClient)
            } catch {
                Self.logger.info("On-device failed (\(error.localizedDescription)), trying next provider")
                failures.append(error.localizedDescription)
            }
        } else {
            failures.append(localClient.unavailabilityReason)
        }

        guard Self.automaticPrivateCloudAllowed else {
            let localReason = failures.filter { !$0.isEmpty }.joined(separator: " ")
            let privacyReason = "Private Cloud Compute is off in Settings → AI."
            throw LocalModelError.unavailable(
                localReason.isEmpty ? privacyReason : "\(localReason) \(privacyReason)"
            )
        }

        // 2. Private Cloud Compute (larger context, still private, no API key)
        if privateCloudClient.isAvailable {
            do {
                Self.logger.debug("Apple-first: trying Private Cloud Compute")
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

    /// Automatic cloud movement is an explicit school-level choice and defaults off.
    static var automaticPrivateCloudAllowed: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
    }
}
