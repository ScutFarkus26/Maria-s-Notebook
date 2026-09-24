import Foundation
import CoreData

// Kept out of PresentationFollowUpTypes.swift: an extension has no dependency fingerprint, so a
// signature edit anywhere in a file that extends CDLessonPresentation recompiles every file that
// uses it. See CLAUDE.md, Build-setting rules.

nonisolated extension CDLessonPresentation {
    /// Unknown future values remain open and display as Keep Watching rather than
    /// silently dropping a shared classroom responsibility.
    var followUpAction: PresentationFollowUpAction? {
        get {
            guard followUpActionRaw != nil else { return nil }
            return PresentationFollowUpAction(rawValue: followUpActionRaw ?? "") ?? .watchWork
        }
        set { followUpActionRaw = newValue?.rawValue }
    }

    var followUpSupport: PresentationFollowUpSupport? {
        get { followUpSupportRaw.flatMap(PresentationFollowUpSupport.init(rawValue:)) }
        set { followUpSupportRaw = newValue?.rawValue }
    }

    var followUpResolution: PresentationFollowUpResolution? {
        get { followUpResolutionRaw.flatMap(PresentationFollowUpResolution.init(rawValue:)) }
        set { followUpResolutionRaw = newValue?.rawValue }
    }

    var followUpEvidence: Set<PresentationFollowUpEvidence> {
        get {
            Set((followUpEvidenceRaw ?? "")
                .split(separator: ",")
                .compactMap { PresentationFollowUpEvidence(rawValue: String($0)) })
        }
        set {
            followUpEvidenceRaw = newValue
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
                .nilIfEmpty
        }
    }

    var hasOpenFollowUp: Bool {
        followUpActionRaw != nil && followUpResolvedAt == nil
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
