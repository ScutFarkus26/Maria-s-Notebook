// WeekDayColumnDropDelegate.swift
// Drop handling for one day of the merged Lessons & Work calendar.
//
// Presentations reorder and merge; work check-ins and work cards are handed
// back up to the host, which owns the save coordinator and the purpose prompt.

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

// MARK: - Drop Delegate for day column

struct WeekDayColumnDropDelegate: DropDelegate {
    private static let logger = Logger.presentations
    let calendar: Calendar
    let viewContext: NSManagedObjectContext
    let allLessonAssignments: [CDLessonAssignment]
    let day: Date
    /// Only presentations take part in ordering, so only their ids and frames
    /// feed the insertion index.
    let orderedPresentationIDs: () -> [UUID]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onDropWorkCheckIn: (UUID, Date) -> Void
    let onDropWork: (UUID, Date) -> Void
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    func dropEntered(info: DropInfo) {
        onTargetChange(true)
        onInsertionIndexChange(computeIndex(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onInsertionIndexChange(computeIndex(info))
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
        let providers = info.itemProviders(for: [UTType.text])
        return performDropFromProvidersAsync(providers: providers, location: info.location)
    }

    private func presentationFrames() -> [UUID: CGRect] {
        let frames = itemFramesProvider()
        return Dictionary(
            orderedPresentationIDs().compactMap { id -> (UUID, CGRect)? in
                guard let rect = frames[id] else { return nil }
                return (id, rect)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func computeIndex(_ info: DropInfo) -> Int? {
        PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: presentationFrames())
    }

    private func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            // A command-click selection arrives as one item carrying every
            // record in it, so a day accepts a whole morning in one drop.
            let payloads = UnifiedCalendarDragPayload.parseAll(ns as String)
            guard !payloads.isEmpty else { return }
            Task { @MainActor in
                for payload in payloads {
                    applyDrop(payload: payload, locationY: location.y)
                }
            }
        }
        return true
    }

    @MainActor
    private func applyDrop(payload: UnifiedCalendarDragPayload, locationY: CGFloat) {
        let normalizedDay = AppCalendar.startOfDay(day)
        switch payload {
        case .presentation(let id):
            applyPresentationDrop(id: id, locationY: locationY)
        case .workCheckIn(let id):
            onDropWorkCheckIn(id, normalizedDay)
        case .work(let id):
            onDropWork(id, normalizedDay)
        case .yearPlanEntry:
            // Year plan entries belong to the student Year Plan calendar.
            break
        }
    }

    /// A drop landing on a pill for the same lesson merges the two rather than
    /// reordering — this is the consolidate-duplicates gesture. Returns the
    /// assignment to merge into, or nil to fall through to reordering.
    @MainActor
    private func mergeTarget(for id: UUID, locationY: CGFloat) -> CDLessonAssignment? {
        guard let source = allLessonAssignments.first(where: { $0.id == id }), !source.isGiven else {
            return nil
        }
        let frames = presentationFrames()
        return orderedPresentationIDs()
            .compactMap { pid in allLessonAssignments.first { $0.id == pid } }
            .first { candidate in
                guard let candidateID = candidate.id, candidateID != id, !candidate.isGiven,
                      candidate.resolvedLessonID == source.resolvedLessonID,
                      let frame = frames[candidateID] else { return false }
                return locationY >= frame.minY && locationY <= frame.maxY
            }
    }

    @MainActor
    private func applyPresentationDrop(id: UUID, locationY: CGFloat) {
        if let target = mergeTarget(for: id, locationY: locationY) {
            PresentationMergeService.merge(
                sourceID: id,
                targetID: target.id ?? UUID(),
                context: viewContext
            )
            return
        }

        let ids = PlanningDropUtils.reordered(
            ids: orderedPresentationIDs(),
            moving: id,
            toLocationY: locationY,
            frames: presentationFrames()
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
        do {
            for itemID in ids {
                if let item = assignmentsByID[itemID], let time = timeMap[itemID] {
                    item.setScheduledFor(time, using: AppCalendar.shared)
                }
            }
            try viewContext.save()

            // Auto-populate year plan entries for the dropped presentation's sequence
            if let droppedItem = allLessonAssignments.first(where: { $0.id == id }),
               droppedItem.state == .scheduled {
                Task {
                    await SequenceAutoPopulateService.autoPopulateSequence(
                        for: droppedItem,
                        scheduledDate: droppedItem.scheduledFor ?? day,
                        context: viewContext
                    )
                }
            }
        } catch {
            Self.logger.warning("Presentations schedule save failed: \(error)")
        }
    }

    /// The day in its new order, each card carrying the half it belongs to.
    ///
    /// Every card already on the day keeps its own half; only the dropped one
    /// takes a new one, inherited from the card it landed under. That is the
    /// whole AM/PM gesture — and it is also what keeps a reorder honest, since
    /// dragging a morning lesson below the afternoon run makes it an afternoon
    /// lesson rather than leaving it stranded in the wrong half.
    @MainActor
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
