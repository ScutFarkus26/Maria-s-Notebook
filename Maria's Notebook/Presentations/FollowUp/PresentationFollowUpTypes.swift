import Foundation

enum PresentationFollowUpAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case watchWork
    case checkWork
    case planSupport
    case planNextPresentation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchWork: "Watch Their Work"
        case .checkWork: "Check Work"
        case .planSupport: "Plan Support"
        case .planNextPresentation: "Plan Next Presentation"
        }
    }

    var shortTitle: String {
        switch self {
        case .watchWork: "Keep Watching"
        case .checkWork: "Check Work"
        case .planSupport: "Plan Support"
        case .planNextPresentation: "Plan Next"
        }
    }

    var systemImage: String {
        switch self {
        case .watchWork: "eye"
        case .checkWork: "checklist"
        case .planSupport: "person.crop.circle.badge.questionmark"
        case .planNextPresentation: "book.pages"
        }
    }
}

enum PresentationFollowUpSupport: String, CaseIterable, Identifiable, Codable, Sendable {
    case represent
    case followUpPresentation
    case confer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .represent: "Re-present This Lesson"
        case .followUpPresentation: "Give a Follow-Up Presentation"
        case .confer: "Confer With the Child"
        }
    }
}

enum PresentationFollowUpEvidence: String, CaseIterable, Identifiable, Codable, Sendable {
    case choseIndependently
    case returnedOrRepeated
    case concentrated
    case usedMaterialAccurately
    case encounteredDifficulty
    case soughtHelpOrCollaborated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .choseIndependently: "Chose the work independently"
        case .returnedOrRepeated: "Returned to or repeated it"
        case .concentrated: "Concentrated"
        case .usedMaterialAccurately: "Used the material accurately"
        case .encounteredDifficulty: "Encountered difficulty"
        case .soughtHelpOrCollaborated: "Sought help or collaborated"
        }
    }
}

enum PresentationFollowUpResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case continueIndependentWork
    case supportOrRepresent
    case readyForNextPresentation
    case noFurtherFollowUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueIndependentWork: "Continue Independent Work"
        case .supportOrRepresent: "Offer Support or Re-present"
        case .readyForNextPresentation: "Ready for a Related or Next Lesson"
        case .noFurtherFollowUp: "No Further Follow-Up Needed"
        }
    }

    var systemImage: String {
        switch self {
        case .continueIndependentWork: "arrow.forward.circle"
        case .supportOrRepresent: "arrow.counterclockwise.circle"
        case .readyForNextPresentation: "book.pages.fill"
        case .noFurtherFollowUp: "checkmark.circle"
        }
    }
}

extension CDLessonPresentation {
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
