//
//  SequenceLadder.swift
//  Cosmic Daybook
//
//  One sub-area as a ladder: its lessons in order, and every child standing
//  on the step she is up to.
//
//  A child's frontier is the step after the highest one she has been given.
//  She stands there once, with one tier: planned when an open plan names her
//  for it, otherwise ready or practice-open exactly as the ready queue says,
//  otherwise unconfirmed (she had the step below, and the guide has neither
//  confirmed nor marked it). A child given the last step is finished; one
//  given nothing is not started, unless a plan already names her for a step,
//  in which case she stands there as planned. Catch-up ghosts are
//  `ReadyGroups`' own, built from the same queue, so the ladder and the Groups
//  page never disagree about who could join.
//
//  Pure, like `ReadyGroups`: it reads a `ReadyQueueSnapshot` and nothing else.
//

import CoreData
import Foundation

nonisolated struct SequenceLadder: Sendable, Equatable {

    /// Where a child stands on her frontier step.
    enum Tier: String, Sendable, Hashable {
        /// The queue holds her ready for this step.
        case ready
        /// The queue holds her almost ready: practice on the step below is open.
        case practiceOpen
        /// An open plan already names her for this step.
        case planned
        /// She had the step below; it is neither confirmed nor mastered.
        case unconfirmed
    }

    /// One child on her frontier step.
    struct Rung: Sendable, Hashable, Identifiable {
        let child: ReadyRoster.Child
        let tier: Tier
        /// The highest step she has been given (1-based); nil when she has
        /// been given none and stands here only because she is planned.
        let lastStepGiven: Int?
        /// Why practice holds her (`.practiceOpen`).
        let reason: String?
        /// School days since the step below was given (`.ready`, `.practiceOpen`).
        let waitSchoolDays: Int?
        /// The plan's date (`.planned`); nil for an undated plan.
        let plannedDate: Date?
        /// Her latest presented assignment of the step below, to confirm on
        /// (`.unconfirmed`); nil when the record holds only a presentation row.
        let confirmAssignmentID: NSManagedObjectID?

        var id: String { child.id }
    }

    /// One lesson of the sub-area.
    struct Step: Sendable, Hashable, Identifiable {
        let position: LessonSequenceOrder.Position
        /// The children whose frontier this is, by name.
        let children: [Rung]
        /// "Could join after N" ghosts, as `ReadyGroups` puts them on this
        /// lesson's card; each child also stands on her own rung below.
        let catchUp: [LessonGroup.CatchUp]

        var id: String { position.lessonID }
    }

    let area: String
    let sequence: String
    /// The sub-area's lessons in order.
    let steps: [Step]
    /// Given nothing in the sub-area and planned for nothing in it, by name.
    let notStarted: [ReadyRoster.Child]
    /// Given the last step, by name.
    let finished: [ReadyRoster.Child]

    /// Builds the ladder for one area + sequence (trimmed, case-insensitive);
    /// nil when the library has no such sub-area.
    ///
    /// - Parameters:
    ///   - snapshot: narrowed with `filtered(levels:)` first for a level filter.
    ///   - schoolDaysSince: as for `ReadyGroups.build`.
    static func build(
        area: String,
        sequence: String,
        from snapshot: ReadyQueueSnapshot,
        schoolDaysSince: (Date) -> Int
    ) -> SequenceLadder? {
        let lessonIDs = snapshot.order.lessonIDs(area: area, sequence: sequence)
        let positions = lessonIDs.compactMap(snapshot.order.position(of:))
        guard let first = positions.first, positions.count == lessonIDs.count else { return nil }

        var placer = Placer(snapshot: snapshot, lessonIDs: lessonIDs)
        for child in snapshot.roster.children.values {
            placer.place(child, schoolDaysSince: schoolDaysSince)
        }
        let ghosts = catchUps(lessonIDs: Set(lessonIDs), in: snapshot, schoolDaysSince: schoolDaysSince)
        let steps = positions.map { position in
            Step(
                position: position,
                children: (placer.rungs[position.lessonID] ?? [])
                    .sorted { ReadyRoster.Child.precedes($0.child, $1.child) },
                catchUp: ghosts.group(for: position.lessonID)?.catchUp ?? []
            )
        }
        return SequenceLadder(
            area: first.area,
            sequence: first.sequence,
            steps: steps,
            notStarted: placer.notStarted.sorted(by: ReadyRoster.Child.precedes),
            finished: placer.finished.sorted(by: ReadyRoster.Child.precedes)
        )
    }

    /// `ReadyGroups` over this sub-area's part of the queue: every card and
    /// ghost on these lessons depends only on items proposing one of them.
    private static func catchUps(
        lessonIDs: Set<String>,
        in snapshot: ReadyQueueSnapshot,
        schoolDaysSince: (Date) -> Int
    ) -> ReadyGroups {
        let scoped = ReadyQueueSnapshot(
            items: snapshot.items.filter { lessonIDs.contains($0.nextLessonID) },
            index: snapshot.index,
            order: snapshot.order,
            roster: snapshot.roster
        )
        return ReadyGroups.build(from: scoped, schoolDaysSince: schoolDaysSince)
    }

    // MARK: - Placing

    /// Puts each child on her frontier, in the finished list, or in the
    /// not-started list.
    private struct Placer {
        let snapshot: ReadyQueueSnapshot
        let lessonIDs: [String]
        let itemsByKey: [String: ReadyForNextItem]
        var rungs: [String: [Rung]] = [:]
        var notStarted: [ReadyRoster.Child] = []
        var finished: [ReadyRoster.Child] = []

        init(snapshot: ReadyQueueSnapshot, lessonIDs: [String]) {
            self.snapshot = snapshot
            self.lessonIDs = lessonIDs
            var byKey: [String: ReadyForNextItem] = [:]
            for item in snapshot.items { byKey[item.id] = item }
            itemsByKey = byKey
        }

        mutating func place(_ child: ReadyRoster.Child, schoolDaysSince: (Date) -> Int) {
            let index = snapshot.index
            if let highest = lessonIDs.lastIndex(where: { index.given(student: child.id, lesson: $0) != nil }) {
                guard highest + 1 < lessonIDs.count else {
                    finished.append(child)
                    return
                }
                let frontier = lessonIDs[highest + 1]
                rungs[frontier, default: []].append(rung(
                    child, frontier: frontier, below: lessonIDs[highest], lastStepGiven: highest + 1,
                    schoolDaysSince: schoolDaysSince
                ))
            } else if let planned = lessonIDs.first(where: { index.hasOpenPlan(student: child.id, lesson: $0) }) {
                rungs[planned, default: []].append(plannedRung(child, lessonID: planned, lastStepGiven: nil))
            } else {
                notStarted.append(child)
            }
        }

        private func rung(
            _ child: ReadyRoster.Child, frontier: String, below: String, lastStepGiven: Int,
            schoolDaysSince: (Date) -> Int
        ) -> Rung {
            if snapshot.index.hasOpenPlan(student: child.id, lesson: frontier) {
                return plannedRung(child, lessonID: frontier, lastStepGiven: lastStepGiven)
            }
            // `ReadyForNextItem.id`: one item per child and proposed lesson.
            if let item = itemsByKey["\(child.id)|\(frontier)"] {
                return Rung(
                    child: child,
                    tier: item.tier == .ready ? .ready : .practiceOpen,
                    lastStepGiven: lastStepGiven,
                    reason: item.tier == .ready ? nil : item.reasons.joined(separator: "; "),
                    waitSchoolDays: item.basisDate.map(schoolDaysSince),
                    plannedDate: nil,
                    confirmAssignmentID: nil
                )
            }
            return Rung(
                child: child, tier: .unconfirmed, lastStepGiven: lastStepGiven, reason: nil,
                waitSchoolDays: nil, plannedDate: nil,
                confirmAssignmentID: snapshot.index.latestPresentedAssignmentByLesson[below]?[child.id]
            )
        }

        private func plannedRung(_ child: ReadyRoster.Child, lessonID: String, lastStepGiven: Int?) -> Rung {
            let plan = snapshot.index.openPlans(lesson: lessonID).first { $0.studentIDs.contains(child.id) }
            return Rung(
                child: child, tier: .planned, lastStepGiven: lastStepGiven, reason: nil,
                waitSchoolDays: nil, plannedDate: plan?.date, confirmAssignmentID: nil
            )
        }
    }
}
