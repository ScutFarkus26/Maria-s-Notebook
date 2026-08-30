// LessonsAndWorkPartition.swift
// The workspace's records, split into their lists exactly once.
//
// `LessonsAndWorkTriage` answers "where does this one record belong?". This
// type asks that question once per record for a whole screenful and keeps the
// answers, so the lists, the card badges and the picker's counts all read the
// same split instead of each re-deriving it.
//
// That matters for more than tidiness. Placing one work item runs
// `WorkAgingPolicy.lastMeaningfulTouchDate` over its check-ins and notes and
// then a school-day count through `SchoolDayCalculationCache` — cheap once,
// wasteful once per consumer per body pass. Before this type existed the
// Attention list and the work grid ran the rule over the same array on the same
// pass, and a third copy of it badged the cards.
//
// Build it on a debounced data-change path, never inside a `body` computed
// property.

import CoreData
import Foundation

// MARK: - The split

/// Records of one kind, grouped by the list they belong in.
///
/// Deliberately generic and free of Core Data so the structural guarantee —
/// every record lands in exactly one list, none is dropped, none is
/// duplicated — can be tested without a store.
struct TriageSplit<Record> {
    let attention: [Record]
    let scheduled: [Record]
    let toSchedule: [Record]
    /// Finished records. Not shown in the workspace; reachable through Logs.
    let done: [Record]

    /// Splits `records`, calling `bucket` exactly once per record and keeping
    /// the input order within each list.
    init(_ records: [Record], bucket: (Record) -> TriageBucket) {
        var attention: [Record] = []
        var scheduled: [Record] = []
        var toSchedule: [Record] = []
        var done: [Record] = []

        for record in records {
            switch bucket(record) {
            case .attention: attention.append(record)
            case .scheduled: scheduled.append(record)
            case .toSchedule: toSchedule.append(record)
            case .done: done.append(record)
            }
        }

        self.attention = attention
        self.scheduled = scheduled
        self.toSchedule = toSchedule
        self.done = done
    }

    /// An empty split, for the state before any data has loaded.
    init() {
        self.init([], bucket: { _ in .done })
    }

    subscript(bucket: TriageBucket) -> [Record] {
        switch bucket {
        case .attention: attention
        case .scheduled: scheduled
        case .toSchedule: toSchedule
        case .done: done
        }
    }

    /// How many records the workspace shows — everything except `.done`.
    var workspaceCount: Int {
        attention.count + scheduled.count + toSchedule.count
    }
}

// MARK: - The workspace's partition

/// One screenful of Lessons & Work, triaged.
///
/// Presentations and work stay in separate splits because the lists render them
/// as different rows — observe the child, versus inspect the work — even where
/// they share a bucket.
struct LessonsAndWorkPartition {
    let presentations: TriageSplit<CDLessonAssignment>
    let work: TriageSplit<CDWorkModel>

    init(
        presentations: TriageSplit<CDLessonAssignment> = .init(),
        work: TriageSplit<CDWorkModel> = .init()
    ) {
        self.presentations = presentations
        self.work = work
    }

    /// Triages a whole screenful in one pass.
    ///
    /// - Parameters:
    ///   - openWork: work already fetched with `checkIns` and `unifiedNotes`
    ///     prefetched. Passing them per row keeps the rule from faulting each
    ///     relationship one item at a time.
    ///   - assignments: the presentations on screen.
    ///   - unresolvedFollowUpIDs: built once with
    ///     `LessonsAndWorkTriage.unresolvedFollowUpAssignmentIDs`, so the
    ///     follow-up question is not re-queried per row.
    @MainActor
    init(
        openWork: [CDWorkModel],
        assignments: [CDLessonAssignment],
        unresolvedFollowUpIDs: Set<UUID>,
        context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared,
        asOf now: Date = Date()
    ) {
        self.init(
            presentations: TriageSplit(assignments) { assignment in
                LessonsAndWorkTriage.bucket(
                    for: assignment,
                    unresolvedFollowUpIDs: unresolvedFollowUpIDs
                )
            },
            work: TriageSplit(openWork) { item in
                LessonsAndWorkTriage.bucket(
                    for: item,
                    context: context,
                    checkIns: (item.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [],
                    notes: (item.unifiedNotes?.allObjects as? [CDNote]) ?? [],
                    calendar: calendar,
                    asOf: now
                )
            }
        )
    }

    /// Everything in one list, presentations before work — the order the
    /// Attention list already renders them in.
    func count(_ bucket: TriageBucket) -> Int {
        presentations[bucket].count + work[bucket].count
    }

    /// True when the bucket has nothing to show.
    func isEmpty(_ bucket: TriageBucket) -> Bool {
        count(bucket) == 0
    }
}
