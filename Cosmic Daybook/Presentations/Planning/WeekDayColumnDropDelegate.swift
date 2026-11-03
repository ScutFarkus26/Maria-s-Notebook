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
    /// Saves the drop and, when that fails, raises the shared "Couldn't Save" alert.
    let saveCoordinator: SaveCoordinator
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
        // Presentations land together, in the order they were dragged, and
        // check-ins are applied together; work cards go one at a time.
        var presentationIDs: [UUID] = []
        var checkInIDs: [UUID] = []
        for payload in payloads {
            switch payload {
            case .presentation(let id):
                if !presentationIDs.contains(id) { presentationIDs.append(id) }
            case .workCheckIn(let id):
                checkInIDs.append(id)
            case .work(let id):
                onDropWork(id, AppCalendar.startOfDay(day))
            case .yearPlanEntry:
                // Year plan entries belong to the student Year Plan calendar.
                break
            }
        }
        if !presentationIDs.isEmpty {
            applyPresentationDrop(ids: presentationIDs, locationY: location.y)
        }
        if !checkInIDs.isEmpty {
            onDropWorkCheckIns(checkInIDs, AppCalendar.startOfDay(day))
        }
    }

    private func presentationFrames() -> [UUID: CGRect] {
        PresentationDropHandling.frames(for: orderedPresentationIDs(), in: itemFramesProvider())
    }

    /// Places every dropped presentation in one pass: a drop on a pill for the
    /// same lesson merges as before, and the rest go in at the drop point, in
    /// the order they were dragged, with the day's times worked out once and
    /// saved once. Placing them one at a time against the column as it was
    /// drawn gave every one the same slot (bug hunt 2026-10-17 #47).
    private func applyPresentationDrop(ids droppedIDs: [UUID], locationY: CGFloat) {
        let frames = presentationFrames()
        let (placed, merged) = mergeWhereDropped(droppedIDs, locationY: locationY, frames: frames)
        guard !placed.isEmpty else { return }

        // A card merged away is deleted: it takes no slot on the day, and is
        // never written to again (review of bug hunt 2026-10-17 #47).
        let ordered = orderedPresentationIDs().filter { !merged.contains($0) }
        let ids = Self.ordering(ordered, inserting: placed, atLocationY: locationY, frames: frames)
        // One pass over the day's assignments instead of a linear scan per id —
        // every drop now writes and saves for real, so a big day would repeat
        // that scan for every pill in it.
        let assignmentsByID = Dictionary(
            allLessonAssignments.compactMap { assignment -> (UUID, CDLessonAssignment)? in
                guard !assignment.isDeleted, assignment.managedObjectContext != nil,
                      let id = assignment.id else { return nil }
                return (id, assignment)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let timeMap = DayHalfPlanner.times(
            for: placements(ordering: ids, dropped: Set(placed), lookup: assignmentsByID),
            on: day,
            using: calendar,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        var touched: [CDLessonAssignment] = []
        for itemID in ids {
            if let item = assignmentsByID[itemID], let time = timeMap[itemID] {
                item.setScheduledFor(time, using: AppCalendar.shared)
                touched.append(item)
            }
        }
        guard save(touched) else { return }

        for id in placed {
            if let droppedItem = assignmentsByID[id] {
                PresentationDropHandling.autoPopulateSequence(
                    for: droppedItem, fallbackDate: { day }, context: viewContext
                )
            }
        }
    }

    /// Merges each dropped card that landed on a pill for the same lesson into
    /// it, and returns the rest, in the order given, to be placed. A dropped
    /// card merges only into one that stays, never another of the batch.
    private func mergeWhereDropped(
        _ droppedIDs: [UUID], locationY: CGFloat, frames: [UUID: CGRect]
    ) -> (placed: [UUID], merged: Set<UUID>) {
        let candidates = orderedPresentationIDs()
            .filter { !droppedIDs.contains($0) }
            .compactMap { pid in allLessonAssignments.first { $0.id == pid } }
        var placed: [UUID] = []
        var merged: Set<UUID> = []
        for id in droppedIDs {
            if let target = PresentationDropHandling.mergeTarget(
                for: id,
                locationY: locationY,
                among: candidates,
                in: allLessonAssignments,
                frames: frames
            ), let targetID = target.id,
               PresentationMergeService.merge(sourceID: id, targetID: targetID, context: viewContext) {
                merged.insert(id)
            } else {
                placed.append(id)
            }
        }
        return (placed, merged)
    }

    /// Saves the drop. A failed save raises the shared alert and puts every
    /// card it touched back as the store has it, rather than leaving the drop
    /// half made in memory (review of bug hunt 2026-10-17 #47).
    private func save(_ touched: [CDLessonAssignment]) -> Bool {
        guard saveCoordinator.save(viewContext, reason: "Drop presentations on a day") else {
            for item in touched where item.managedObjectContext != nil {
                viewContext.refresh(item, mergeChanges: false)
            }
            return false
        }
        return true
    }

    /// The day's presentations with `dropped` taken out and put back together
    /// where the drop landed, first to last in the order given.
    ///
    /// The landing point is found the way a single card's is
    /// (`PlanningDropUtils.reordered`, which drops the moving card's own frame
    /// first), with every dropped card's frame left out, so the boundary is
    /// read among the cards that stay.
    static func ordering(
        _ ordered: [UUID],
        inserting dropped: [UUID],
        atLocationY locationY: CGFloat,
        frames: [UUID: CGRect]
    ) -> [UUID] {
        guard let first = dropped.first else { return ordered }
        let droppedSet = Set(dropped)
        let staying = ordered.filter { !droppedSet.contains($0) }
        let stayingFrames = frames.filter { !droppedSet.contains($0.key) }
        var ids = PlanningDropUtils.reordered(
            ids: staying, moving: first, toLocationY: locationY, frames: stayingFrames
        )
        let index = (ids.firstIndex(of: first) ?? ids.count - 1) + 1
        ids.insert(contentsOf: dropped.dropFirst(), at: index)
        return ids
    }

    /// The day in its new order, each card carrying the half it belongs to.
    ///
    /// Every card already on the day keeps its own half; only the dropped ones
    /// take a new one, inherited from the card they landed under. That is the
    /// whole AM/PM gesture — and it is also what keeps a reorder honest, since
    /// dragging a morning lesson below the afternoon run makes it an afternoon
    /// lesson rather than leaving it stranded in the wrong half.
    private func placements(
        ordering ids: [UUID],
        dropped: Set<UUID>,
        lookup: [UUID: CDLessonAssignment]
    ) -> [DayHalfPlanner.Placement] {
        func half(_ itemID: UUID) -> DayPeriod {
            guard let scheduled = lookup[itemID]?.scheduledFor else { return .morning }
            return DayPeriod(scheduledFor: scheduled, using: calendar)
        }

        // The dropped cards sit together, so the first of them is where the
        // drop landed among the others, and they all take that half.
        let insertionIndex = ids.firstIndex { dropped.contains($0) } ?? ids.count
        let inherited = DayHalfPlanner.inheritedPeriod(
            insertingAt: insertionIndex,
            into: ids.filter { !dropped.contains($0) }.map(half)
        )
        // A time the guide set (10:30 through Claude) stays put; only the
        // dropped cards and the ordering slots around them are renumbered.
        return ids.map { itemID in
            dropped.contains(itemID)
                ? DayHalfPlanner.Placement(id: itemID, period: inherited)
                : DayHalfPlanner.Placement(
                    id: itemID,
                    period: half(itemID),
                    keptTime: DayHalfPlanner.keptTime(of: lookup[itemID]?.scheduledFor, using: calendar)
                )
        }
    }
}
