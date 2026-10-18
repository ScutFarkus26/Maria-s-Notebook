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

    /// Why no request can be served right now, in plain words, for screens
    /// that say so ahead of time: Apple Intelligence is off, still
    /// downloading, or not on this device. Parsha's pages used to say "isn't
    /// available on this device" for all three (bug hunt 2026-10-17 #16).
    static var unavailabilityReason: String {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        let reason = LocalModelClient().unavailabilityReason
        return reason.isEmpty ? AppleIntelligenceMessages.notAvailable : reason
        #else
        AppleIntelligenceMessages.notInThisVersion
        #endif
    }

    // MARK: - MCPClientProtocol — generateText

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await generateText(
            prompt: prompt, systemMessage: nil,
            temperature: temperature, maxTokens: nil,
            timeout: nil
        )
    }

    func generateText(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        let deadline = Deadline(limit: timeout)
        return try await route { client in
            try await client.generateText(
                prompt: prompt, systemMessage: systemMessage,
                temperature: temperature, maxTokens: maxTokens,
                timeout: try deadline.remaining()
            )
        }
    }

    // MARK: - MCPClientProtocol — generateStructuredJSON

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await generateStructuredJSON(
            prompt: prompt, systemMessage: nil,
            temperature: temperature, maxTokens: nil,
            timeout: nil
        )
    }

    func generateStructuredJSON(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        let deadline = Deadline(limit: timeout)
        return try await route { client in
            try await client.generateStructuredJSON(
                prompt: prompt, systemMessage: systemMessage,
                temperature: temperature, maxTokens: maxTokens,
                timeout: try deadline.remaining()
            )
        }
    }

    // MARK: - MCPClientProtocol — sendConversation

    func sendConversation(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval?
    ) async throws -> String {
        let deadline = Deadline(limit: timeout)
        return try await route { client in
            try await client.sendConversation(
                messages: messages,
                systemMessage: systemMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                timeout: try deadline.remaining()
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
        timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let deadline = Deadline(limit: timeout)
        return try await route { client in
            try await client.streamConversation(
                messages: messages,
                systemMessage: systemMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                timeout: try deadline.remaining(),
                onText: onText
            )
        }
    }

    // MARK: - MCPClientProtocol — streamChat

    // Ask AI's answers. Only the on-device model has the notebook tools; when
    // it fails and Private Cloud Compute answers instead, the records the
    // failed attempt looked up are dropped, so the answer doesn't list
    // sources it never used (bug hunt 2026-10-11 #53). When a tool already
    // saved something, the failure stands: Private Cloud would answer
    // without tools, and the guide would ask again (bug hunt 2026-10-17 #9).
    // swiftlint:disable:next function_parameter_count
    func streamChat(
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        tools: ChatToolContext,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        try await Self.streamChat(
            local: localClient,
            cloud: { self.privateCloudClient },
            cloudAllowed: Self.automaticPrivateCloudAllowed,
            messages: messages,
            systemMessage: systemMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            tools: tools,
            onText: onText
        )
        #else
        throw LocalModelError.unavailable(AppleIntelligenceMessages.notInThisVersion)
        #endif
    }

    /// `streamChat`'s routing, apart from the real models so a test can see
    /// the failed attempt's sources dropped through this wiring, not only
    /// through `route` (review (b) 2026-10-11).
    static func streamChat( // swiftlint:disable:this function_parameter_count
        local: any RoutableModelClient,
        cloud: () -> any RoutableModelClient,
        cloudAllowed: Bool,
        messages: [[String: String]],
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int,
        tools: ChatToolContext,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let answer: (any MCPClientProtocol) async throws -> String = { client in
            try await client.streamChat(
                messages: messages,
                systemMessage: systemMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                tools: tools,
                onText: onText
            )
        }
        return try await route(
            local: local, cloud: cloud, cloudAllowed: cloudAllowed,
            fallbackAllowed: { tools.writes.isEmpty },
            beforeFallback: { _ = await tools.sources.consume() }, answer
        )
    }

    // MARK: - Routing Engine

    /// Tries Apple's models in order: on-device, then Private Cloud Compute.
    private func route<T>(_ work: (any MCPClientProtocol) async throws -> T) async throws -> T {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        try await Self.route(
            local: localClient,
            cloud: { self.privateCloudClient },
            cloudAllowed: Self.automaticPrivateCloudAllowed,
            work
        )
        #else
        throw LocalModelError.unavailable(AppleIntelligenceMessages.notInThisVersion)
        #endif
    }

    /// The routing rule, apart from the real models so it can be tested:
    /// `local` first; then, when `cloudAllowed` and the failed attempt left
    /// `fallbackAllowed`, `cloud`, after `beforeFallback` has undone what the
    /// failed local attempt left behind.
    ///
    /// A cancelled request stops here. It used to be taken for a failure and
    /// sent again to Private Cloud Compute, so New Chat or a closed window
    /// mid-answer still spent a cloud request (bug hunt 2026-10-11 #53).
    static func route<T>(
        local: any RoutableModelClient,
        cloud: () -> any RoutableModelClient,
        cloudAllowed: Bool,
        fallbackAllowed: () -> Bool = { true },
        beforeFallback: () async -> Void = {},
        _ work: (any MCPClientProtocol) async throws -> T
    ) async throws -> T {
        var failures: [String] = []

        // 1. Apple Intelligence on-device (fastest, fully private, free)
        if local.isAvailable {
            do {
                logger.debug("Apple-first: trying on-device")
                return try await work(local)
            } catch {
                if isCancellation(error) { throw error }
                logger.info("On-device failed (\(error.localizedDescription)), trying next provider")
                // With Private Cloud off there's nowhere else to go, so the
                // on-device failure is the answer, said in its own words; the
                // same when the attempt already changed the notebook.
                guard cloudAllowed, fallbackAllowed() else { throw error }
                failures.append(plainReason(for: error))
                await beforeFallback()
            }
        } else {
            failures.append(local.unavailabilityReason)
        }

        guard cloudAllowed else {
            let localReason = joinedReasons(failures)
            let privacyReason = AppleIntelligenceMessages.privateCloudOff
            throw LocalModelError.unavailable(
                localReason.isEmpty ? privacyReason : "\(localReason) \(privacyReason)"
            )
        }
        try Task.checkCancellation()

        // 2. Private Cloud Compute (larger context, still private, no API key)
        let cloud = cloud()
        if cloud.isAvailable {
            do {
                logger.debug("Apple-first: trying Private Cloud Compute")
                return try await work(cloud)
            } catch {
                if isCancellation(error) { throw error }
                logger.info("Private Cloud Compute failed (\(error.localizedDescription))")
                failures.append(plainReason(for: error))
            }
        } else {
            failures.append(cloud.unavailabilityReason)
        }

        let reason = joinedReasons(failures)
        throw LocalModelError.unavailable(
            reason.isEmpty ? AppleIntelligenceMessages.notAvailable : reason
        )
    }

    /// The request was called off (its task cancelled), as opposed to failing.
    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }

    /// A provider's failure as a sentence the teacher can read: Apple
    /// Intelligence's own errors already are one; anything else (a decoding
    /// error, a network error) would be raw system text, so it becomes the
    /// general one. The raw text is in the log line above.
    private static func plainReason(for error: Error) -> String {
        if let local = error as? LocalModelError { return local.errorDescription ?? "" }
        return AppErrorMessages.aiMessage(for: error)
    }

    /// The distinct, non-empty reasons in order, as one message.
    private static func joinedReasons(_ reasons: [String]) -> String {
        var seen = Set<String>()
        return reasons.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " ")
    }

    /// Automatic cloud movement is an explicit school-level choice and defaults off.
    static var automaticPrivateCloudAllowed: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
    }
}

// MARK: - Time limits and the unavailable line

extension AIClientRouter {
    /// The line a screen shows while its AI feature is off: why, then
    /// "Until then, <off>." only when that will pass (Apple Intelligence is
    /// turned off or still getting ready). A device that can't run it, or a
    /// reason the app can't name, gets "<Off>." without a promise
    /// (review (b) 2026-10-17, #8).
    static func unavailabilityNotice(_ off: String, reason: String = unavailabilityReason) -> String {
        let passes = reason == AppleIntelligenceMessages.turnOn
            || reason == AppleIntelligenceMessages.stillGettingReady
        if passes { return "\(reason) Until then, \(off)." }
        return "\(reason) \(off.prefix(1).uppercased())\(off.dropFirst())."
    }

    /// One request's time limit, shared by its attempts: Private Cloud
    /// Compute gets only what the on-device attempt left, so a step given
    /// 120 seconds can't take 240 (review (b) 2026-10-17, #7).
    nonisolated struct Deadline: Sendable {
        private let end: ContinuousClock.Instant?

        /// No limit when `seconds` is nil or not positive, as for
        /// `ModelRequestTimeout`.
        init(limit seconds: TimeInterval?, from now: ContinuousClock.Instant = .now) {
            if let seconds, seconds > 0 {
                end = now.advanced(by: .seconds(seconds))
            } else {
                end = nil
            }
        }

        /// The seconds left for the next attempt, nil without a limit.
        /// Throws "took too long" when none are left.
        func remaining(at now: ContinuousClock.Instant = .now) throws -> TimeInterval? {
            guard let end else { return nil }
            let left = now.duration(to: end)
            guard left > .zero else {
                throw LocalModelError.generationFailed(AppleIntelligenceMessages.timedOut)
            }
            let parts = left.components
            return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        }
    }
}
