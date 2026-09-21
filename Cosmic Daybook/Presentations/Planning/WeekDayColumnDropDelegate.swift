// WeekDayColumnDropDelegate.swift
// Drop handling for one day of the merged Lessons & Work calendar.
//
// Presentations reorder and merge; work check-ins and work cards are handed
// back up to the host, which owns the save coordinator and the purpose prompt.
//
// The highlight, the insertion indicator and the pasteboard read come from
// `PresentationDropTarget`; what is here is the day column itself.

import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Drop Delegate for day column

struct WeekDayColumnDropDelegate: PresentationDropTarget {
    let calendar: Calendar
    let viewContext: NSManagedObjectContext
    let allLessonAssignments: [CDLessonAssignment]
    let day: Date
    /// Only presentations take part in ordering, so only their ids and frames
    /// feed the insertion index.
    let orderedPresentationIDs: () -> [UUID]
    let itemFramesProvider: () -> [UUID: CGRect]
    /// Every check-in in one drop, together: a grouped pill hands over all of
    /// its children at once, and they are one move rather than one each.
    let onDropWorkCheckIns: ([UUID], Date) -> Void
    let onDropWork: (UUID, Date) -> Void
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    // MARK: - PresentationDropTarget

    func insertionIndex(at location: CGPoint) -> Int? {
        PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: presentationFrames())
    }

    func handleDroppedText(_ text: String, location: CGPoint) {
        // A command-click selection arrives as one item carrying every record
        // in it, so a day accepts a whole morning in one drop.
        let payloads = UnifiedCalendarDragPayload.parseAll(text)
        guard !payloads.isEmpty else { return }
        // Check-ins are collected and applied together; everything else lands
        // in the order it was dragged.
        var checkInIDs: [UUID] = []
        for payload in payloads {
            if case .workCheckIn(let id) = payload {
                checkInIDs.append(id)
            } else {
                applyDrop(payload: payload, locationY: location.y)
            }
        }
        if !checkInIDs.isEmpty {
            onDropWorkCheckIns(checkInIDs, AppCalendar.startOfDay(day))
        }
    }

    private func presentationFrames() -> [UUID: CGRect] {
        PresentationDropHandling.frames(for: orderedPresentationIDs(), in: itemFramesProvider())
    }

    private func applyDrop(payload: UnifiedCalendarDragPayload, locationY: CGFloat) {
        switch payload {
        case .presentation(let id):
            applyPresentationDrop(id: id, locationY: locationY)
        case .work(let id):
            onDropWork(id, AppCalendar.startOfDay(day))
        case .workCheckIn:
            // Batched by the caller — see handleDroppedText.
            break
        case .yearPlanEntry:
            // Year plan entries belong to the student Year Plan calendar.
            break
        }
    }

    private func applyPresentationDrop(id: UUID, locationY: CGFloat) {
        let ordered = orderedPresentationIDs()
        let frames = presentationFrames()
        if let target = PresentationDropHandling.mergeTarget(
            for: id,
            locationY: locationY,
            among: ordered.compactMap { pid in allLessonAssignments.first { $0.id == pid } },
            in: allLessonAssignments,
            frames: frames
        ) {
            PresentationMergeService.merge(
                sourceID: id,
                targetID: target.id ?? UUID(),
                context: viewContext
            )
            return
        }

        let ids = PlanningDropUtils.reordered(
            ids: ordered,
            moving: id,
            toLocationY: locationY,
            frames: frames
        )
        // One pass over the day's assignments instead of a linear scan per id —
        // every drop now writes and saves for real, so a big day would repeat
        // that scan for every pill in it.
        let assignmentsByID = Dictionary(
            allLessonAssignments.compactMap { assignment in assignment.id.map { ($0, assignment) } },
            uniquingKeysWith: { first, _ in first }
        )
        let timeMap = DayHalfPlanner.times(
            for: placements(ordering: ids, dropped: id, lookup: assignmentsByID),
            on: day,
            using: calendar,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        for itemID in ids {
            if let item = assignmentsByID[itemID], let time = timeMap[itemID] {
                item.setScheduledFor(time, using: AppCalendar.shared)
            }
        }
        guard viewContext.safeSave() else { return }

        if let droppedItem = assignmentsByID[id] {
            PresentationDropHandling.autoPopulateSequence(
                for: droppedItem, fallbackDate: { day }, context: viewContext
            )
        }
    }

    /// The day in its new order, each card carrying the half it belongs to.
    ///
    /// Every card already on the day keeps its own half; only the dropped one
    /// takes a new one, inherited from the card it landed under. That is the
    /// whole AM/PM gesture — and it is also what keeps a reorder honest, since
    /// dragging a morning lesson below the afternoon run makes it an afternoon
    /// lesson rather than leaving it stranded in the wrong half.
    private func placements(
        ordering ids: [UUID],
        dropped id: UUID,
        lookup: [UUID: CDLessonAssignment]
    ) -> [DayHalfPlanner.Placement] {
        func half(_ itemID: UUID) -> DayPeriod {
            guard let scheduled = lookup[itemID]?.scheduledFor else { return .morning }
            return DayPeriod(scheduledFor: scheduled, using: calendar)
        }

        let insertionIndex = ids.firstIndex(of: id) ?? ids.count
        let inherited = DayHalfPlanner.inheritedPeriod(
            insertingAt: insertionIndex,
            into: ids.filter { $0 != id }.map(half)
        )
        return ids.map { itemID in
            DayHalfPlanner.Placement(id: itemID, period: itemID == id ? inherited : half(itemID))
        }
    }
}
