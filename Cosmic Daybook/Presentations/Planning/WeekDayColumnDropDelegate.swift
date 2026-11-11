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
    /// Each presentation's half and whether it has a set time, so a drop lands
    /// only among the untimed cards (`WeekDayColumn.untimedInsertionIndex`).
    var cardPlaces: () -> [UUID: WeekDayColumn.CardPlace] = { [:] }
    /// Every check-in in one drop, together: a grouped pill hands over all of
    /// its children at once, and they are one move rather than one each.
    let onDropWorkCheckIns: ([UUID], Date) -> Void
    let onDropWork: (UUID, Date) -> Void
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    // MARK: - PresentationDropTarget

    /// Where the drop would land among the cards on screen, top to bottom,
    /// moved past any timed cards in front of it in the same half: a timed
    /// card's time decides its place, so the bar never draws between two of
    /// them (plan "Lesson times on cards", decision 6). The drop itself needs
    /// no such step: a timed card takes no slot when the day is renumbered,
    /// so landing in front of one or behind it stores the same thing.
    func insertionIndex(at location: CGPoint) -> Int? {
        let frames = presentationFrames()
        let raw = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: frames)
        let places = cardPlaces()
        let drawn = frames.sorted { $0.value.minY < $1.value.minY }
            .map { places[$0.key] ?? WeekDayColumn.CardPlace(half: .morning) }
        return WeekDayColumn.untimedInsertionIndex(raw, among: drawn)
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
        // Each card's half and any time set on it, by the rules in
        // `DayHalfPlanner.placementsAfterDrop`: a set time survives the drop.
        let placements = DayHalfPlanner.placementsAfterDrop(
            ordering: ids,
            dropped: Set(placed),
            scheduledFor: Dictionary(
                ids.compactMap { id in assignmentsByID[id]?.scheduledFor.map { (id, $0) } },
                uniquingKeysWith: { first, _ in first }
            ),
            using: calendar
        )
        let timeMap = DayHalfPlanner.times(
            for: placements,
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
                PresentationDropHandling.promoteYearPlanEntries(
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
}
