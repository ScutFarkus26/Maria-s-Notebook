import Foundation

/// One child's choice on the presentation sheet: a decision, and Ready for
/// next as well when the decision is practice or follow-up work. Work to do
/// doesn't hold a child back from the next lesson; re-presenting and keeping
/// watching do.
nonisolated struct PresentationChoice: Equatable, Hashable, Sendable {
    let decision: CaptureFollowUp
    /// Ready for the next lesson alongside the decision's work.
    let alsoReady: Bool

    init(_ decision: CaptureFollowUp, alsoReady: Bool = false) {
        self.decision = decision
        self.alsoReady = alsoReady && decision.createsWork
    }

    /// Ready for the next lesson, on its own or alongside work.
    var isReady: Bool { decision == .readyForNextLesson || alsoReady }

    /// Whether the chip shows as chosen.
    func shows(_ chip: CaptureFollowUp) -> Bool {
        chip == decision || (chip == .readyForNextLesson && alsoReady)
    }

    /// The choice after tapping a chip. Ready for next and practice or
    /// follow-up work go together; any other chip replaces the choice.
    func tapping(_ chip: CaptureFollowUp) -> PresentationChoice {
        switch chip {
        case .readyForNextLesson where decision.createsWork:
            return PresentationChoice(decision, alsoReady: !alsoReady)
        case .practice, .followUpWork:
            // Tapping the chosen work again leaves Ready for next, if it's on.
            if chip == decision { return alsoReady ? PresentationChoice(.readyForNextLesson) : self }
            return PresentationChoice(chip, alsoReady: isReady)
        default:
            return PresentationChoice(chip)
        }
    }

    // MARK: - Later's draft

    /// "practice", or "practice+ready" with Ready for next as well.
    var rawValue: String {
        alsoReady ? decision.rawValue + Self.readySuffix : decision.rawValue
    }

    init?(rawValue: String) {
        let ready = rawValue.hasSuffix(Self.readySuffix)
        let base = ready ? String(rawValue.dropLast(Self.readySuffix.count)) : rawValue
        guard let decision = CaptureFollowUp(rawValue: base) else { return nil }
        self.init(decision, alsoReady: ready)
    }

    private static let readySuffix = "+ready"
}
