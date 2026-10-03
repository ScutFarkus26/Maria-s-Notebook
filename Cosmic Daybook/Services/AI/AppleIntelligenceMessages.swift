// AppleIntelligenceMessages.swift
// The one place Apple Intelligence failures become plain sentences. Notes,
// Stories, Parsha, Planning, Chat, Albums and Insights all read from here, so
// the same failure says the same thing everywhere.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated enum AppleIntelligenceMessages {

    static let busy = "Apple Intelligence is busy. Wait a moment and try again."
    static let tooLong = "That's too much for Apple Intelligence at once. Try something shorter."
    static let refused = "Apple Intelligence can't help with this one. Try rewording it."
    static let timedOut = "Apple Intelligence took too long. Try again."
    static let unsupportedLanguage = "Apple Intelligence doesn't work in this language yet."
    static let unreadable = "Apple Intelligence gave an answer the app couldn't use. Try again."
    static let stillGettingReady = "Apple Intelligence is still getting ready. Try again in a few minutes."
    static let notAvailable = "Apple Intelligence isn't available right now."
    static let deviceNotEligible = "This device doesn't support Apple Intelligence."
    static let notInThisVersion = "Apple Intelligence isn't available in this version of the app."
    static let privateCloudOff = "This needs Private Cloud Compute, which is off. "
        + "You can turn it on in Settings › Intelligence."

    /// "Turn on Apple Intelligence in Settings." in the device's own words.
    static var turnOn: String {
        #if os(macOS)
        "Turn on Apple Intelligence in System Settings."
        #else
        "Turn on Apple Intelligence in Settings."
        #endif
    }

    /// The default for a failure nothing more specific covers. Callers usually
    /// pass their own ("Couldn't make a plan. Try again in a moment.").
    static let fallback = "Couldn't finish that. Try again in a moment."

    /// The message for `error` if it is a Foundation Models failure, else nil.
    static func message(forAny error: Error, fallback: String = AppleIntelligenceMessages.fallback) -> String? {
        #if canImport(FoundationModels)
        if let modelError = error as? LanguageModelError {
            return message(for: modelError, fallback: fallback)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)

    /// A Foundation Models failure, in plain words. `tooLong` lets a caller name
    /// what to cut ("Choose fewer notes and try again.").
    static func message(
        for error: LanguageModelError,
        tooLong: String = AppleIntelligenceMessages.tooLong,
        fallback: String = AppleIntelligenceMessages.fallback
    ) -> String {
        switch error {
        case .rateLimited: return busy
        case .contextSizeExceeded: return tooLong
        case .unsupportedLanguageOrLocale: return unsupportedLanguage
        case .refusal: return refused
        case .timeout: return timedOut
        default: return fallback
        }
    }

    /// Why the on-device model can't be used, or nil when it can.
    static func unavailableMessage(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return turnOn
        case .unavailable(.deviceNotEligible): return deviceNotEligible
        case .unavailable(.modelNotReady): return stillGettingReady
        case .unavailable: return notAvailable
        }
    }

    #endif
}
