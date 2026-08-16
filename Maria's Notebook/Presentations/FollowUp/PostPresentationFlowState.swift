import Foundation

struct PostPresentationFlowState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case lesson
        case reflection
        case followUp
        case closed
    }

    private(set) var phase: Phase = .lesson

    mutating func beginReflection() {
        phase = .reflection
    }

    mutating func reflectionDidDismiss(
        presentationIsRecorded: Bool,
        hasOpenFollowUp: Bool
    ) {
        phase = presentationIsRecorded && hasOpenFollowUp ? .followUp : .lesson
    }

    mutating func showFollowUp() {
        phase = .followUp
    }

    mutating func returnToLesson() {
        phase = .lesson
    }

    mutating func undoPresentation() {
        phase = .lesson
    }

    mutating func close() {
        phase = .closed
    }

    var shouldDismissDetail: Bool { phase == .closed }
}
