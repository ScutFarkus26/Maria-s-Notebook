//
//  LocalModelClient.swift
//  Cosmic Daybook
//
//  MCPClientProtocol implementation backed by Apple's on-device FoundationModels.
//  Guarded behind ENABLE_FOUNDATION_MODELS flag (see Documentation/Architecture/AI.md).
//

import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

/// On-device AI client using Apple Intelligence via FoundationModels framework.
/// Falls back cleanly when Apple Intelligence is unavailable (wrong device, not enabled, etc.).
@available(macOS 26.0, iOS 26.0, *)
final class LocalModelClient: FoundationModelClient {
    // MARK: - Availability

    /// Returns true if the on-device model is ready to accept requests.
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Human-readable description of why the model is unavailable.
    var unavailabilityReason: String {
        AppleIntelligenceMessages.unavailableMessage(for: SystemLanguageModel.default.availability) ?? ""
    }

    // MARK: - FoundationModelClient

    /// On-device session: the default system model, no tools attached.
    func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    func generationOptions(temperature: Double, maxTokens: Int?) -> GenerationOptions {
        .init(temperature: temperature, maximumResponseTokens: maxTokens)
    }
}

// MARK: - Errors

nonisolated enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    /// Shown to the teacher as is, so every case is a plain sentence:
    /// `unavailable` carries one already, and `generationFailed` carries the
    /// translated message (the raw text goes to the log where it's caught).
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.isEmpty ? AppleIntelligenceMessages.notAvailable : reason
        case .contextTooLarge:
            return AppleIntelligenceMessages.tooLong
        case .rateLimited:
            return AppleIntelligenceMessages.busy
        case .invalidJSON:
            return AppleIntelligenceMessages.unreadable
        case .generationFailed(let message):
            return message
        }
    }

    /// Maps FoundationModels.LanguageModelError to LocalModelError.
    static func fromLanguageModel(_ error: LanguageModelError) -> LocalModelError {
        switch error {
        case .contextSizeExceeded:
            return .contextTooLarge
        case .rateLimited:
            return .rateLimited
        default:
            return .generationFailed(AppleIntelligenceMessages.message(for: error))
        }
    }
}

#else

// MARK: - Stub when FoundationModels is unavailable

/// Placeholder error type available regardless of FoundationModels flag.
/// Used by AIClientRouter to compile on all platforms.
nonisolated enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.isEmpty ? AppleIntelligenceMessages.notAvailable : reason
        case .contextTooLarge:
            return AppleIntelligenceMessages.tooLong
        case .rateLimited:
            return AppleIntelligenceMessages.busy
        case .invalidJSON:
            return AppleIntelligenceMessages.unreadable
        case .generationFailed(let message):
            return message
        }
    }
}

#endif
