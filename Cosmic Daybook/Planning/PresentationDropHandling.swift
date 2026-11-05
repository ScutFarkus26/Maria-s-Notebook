// PresentationDropHandling.swift
// The part of a presentation drop that does not depend on where it landed.
//
// Two delegates accept dragged presentations — a planning slot and a day column
// of the merged Lessons & Work calendar — and they differ only in the target:
// what counts as "the list", how the dropped card is re-timed, and which other
// payload kinds the drop understands. Everything around that was written twice:
// the highlight and insertion indicator, pulling the dragged text off the
// pasteboard, narrowing the reported frames to the cards in the list, deciding
// that a drop on a pill for the same lesson means *merge these two*, and filling
// in the year plan behind a newly scheduled presentation.
//
// That shell lives here, so the two targets cannot drift apart in the parts of
// the gesture a guide experiences as one behaviour.

import CoreData
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

/// The half of a planning drop delegate that is the same wherever cards land.
///
/// Conformers supply the two callbacks the host uses to draw the drop state,
/// the insertion index for the list they own, and what to do with the dragged
/// text once it arrives.
protocol PresentationDropTarget: DropDelegate, Sendable {
    var onTargetChange: (Bool) -> Void { get }
    var onInsertionIndexChange: (Int?) -> Void { get }

    /// Where the indicator should sit for a drop at `location`.
    func insertionIndex(at location: CGPoint) -> Int?

    /// Act on one dragged payload string, dropped at `location`.
    func handleDroppedText(_ text: String, location: CGPoint)
}

extension PresentationDropTarget {
    func dropEntered(info: DropInfo) {
        onTargetChange(true)
        onInsertionIndexChange(insertionIndex(at: info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onInsertionIndexChange(insertionIndex(at: info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false)
        onInsertionIndexChange(nil)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let location = info.location
        return PresentationDropHandling.loadDroppedText(
            from: info.itemProviders(for: [UTType.text])
        ) { text in
            handleDroppedText(text, location: location)
        }
    }
}

/// Pieces of a presentation drop that both targets perform identically.
enum PresentationDropHandling {

    /// Reads the dragged text off the first provider that carries any and hands
    /// it back on the main actor.
    ///
    /// - Returns: false when nothing in the drop carries text, which is the
    ///   delegate's way of declining the drop.
    static func loadDroppedText(
        from providers: [NSItemProvider],
        then handle: @escaping @MainActor @Sendable (String) -> Void
    ) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let text = ns as String
            Task { @MainActor in
                handle(text)
            }
        }
        return true
    }

    /// `frames` narrowed to `ids`, which is what the insertion-index maths
    /// wants: cards scrolled out of a lazy stack never report a frame, and
    /// cards from another list must not be counted.
    static func frames(for ids: [UUID], in reported: [UUID: CGRect]) -> [UUID: CGRect] {
        Dictionary(
            ids.compactMap { id -> (UUID, CGRect)? in
                guard let rect = reported[id] else { return nil }
                return (id, rect)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A drop landing on a pill for the same lesson merges the two rather than
    /// reordering — this is the consolidate-duplicates gesture.
    ///
    /// - Returns: the assignment to merge into, or nil to fall through to an
    ///   ordinary reorder.
    static func mergeTarget(
        for id: UUID,
        locationY: CGFloat,
        among candidates: [CDLessonAssignment],
        in all: [CDLessonAssignment],
        frames: [UUID: CGRect]
    ) -> CDLessonAssignment? {
        guard let source = all.first(where: { $0.id == id }), !source.isGiven else {
            return nil
        }
        return candidates.first { candidate in
            guard let candidateID = candidate.id, candidateID != id, !candidate.isGiven,
                  candidate.resolvedLessonID == source.resolvedLessonID,
                  let frame = frames[candidateID] else { return false }
            return locationY >= frame.minY && locationY <= frame.maxY
        }
    }

    /// A presentation that landed on a day: each child's planned year-plan entry for
    /// the lesson follows it there (`YearPlanPromotionService`), entries already
    /// promoted into it move with it, and nothing is laid on the lessons after. A
    /// given one keeps its entries on the day it was given, when that was changed
    /// (bug hunt 2026-11-03 #20). A draft implies nothing, so nothing runs.
    static func promoteYearPlanEntries(
        for assignment: CDLessonAssignment,
        fallbackDate: () -> Date,
        context: NSManagedObjectContext
    ) {
        let day: Date
        switch assignment.state {
        case .scheduled:
            day = assignment.scheduledFor ?? fallbackDate()
        case .presented:
            guard let given = assignment.presentedAt else { return }
            day = given
        case .draft:
            return
        }
        let changed = YearPlanPromotionService.promoteMatchingEntries(
            into: assignment, scheduledFor: day, context: context
        )
        if changed > 0 { _ = context.safeSave() }
    }
}
