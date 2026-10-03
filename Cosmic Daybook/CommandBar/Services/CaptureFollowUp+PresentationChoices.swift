import Foundation

// The presentation sheet's words for the command bar's per-child decisions.
// One vocabulary for one decision: the sheet, the command bar's capture review
// and MCP's record_presentation all write a `CaptureFollowUp` through
// `CaptureFollowUpPersistence`.

nonisolated extension CaptureFollowUp {
    /// The choices the presentation sheet offers, in the order its chips show them.
    static let presentationChoices: [CaptureFollowUp] = [
        .practice, .followUpWork, .represent, .readyForNextLesson, .continueObserving
    ]

    /// The chip's label.
    var chipTitle: String {
        switch self {
        case .none: "No decision"
        case .continueObserving: "Keep watching"
        case .practice: "Practice"
        case .represent: "Re-present"
        case .readyForNextLesson: "Ready for next"
        case .followUpWork: "Follow-up work"
        }
    }

    /// Whether the decision gives the child a piece of work to check later.
    var createsWork: Bool {
        self == .practice || self == .followUpWork
    }
}
