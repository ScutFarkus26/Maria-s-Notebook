//
//  LocalModelError.swift
//  Cosmic Daybook
//
//  The plain-English errors `FoundationModelClient` and `AIClientRouter`
//  throw, with or without FoundationModels in the build.
//

import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

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
        LocalModelError.describe(self)
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

/// Placeholder error type available regardless of FoundationModels flag.
/// Used by AIClientRouter to compile on all platforms.
nonisolated enum LocalModelError: Error, LocalizedError {
    case unavailable(String)
    case contextTooLarge
    case rateLimited
    case invalidJSON
    case generationFailed(String)

    var errorDescription: String? {
        LocalModelError.describe(self)
    }
}

#endif

extension LocalModelError {
    nonisolated static func describe(_ error: LocalModelError) -> String {
        switch error {
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
