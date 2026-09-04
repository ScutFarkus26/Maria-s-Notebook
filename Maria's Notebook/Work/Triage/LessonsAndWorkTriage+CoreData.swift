// LessonsAndWorkTriage+CoreData.swift
// Builds the triage rule's value inputs from managed objects.
//
// Kept apart from the rule itself so `LessonsAndWorkTriage` stays pure and
// testable. Nothing here decides anything — it only reads.

import CoreData
import Foundation

// MARK: - Work

extension WorkTriageInput {
    /// Reads one work item into the values the rule needs.
    ///
    /// Pass `checkIns` and `notes` when the caller already holds them (a list
    /// that fetched them in a batch), so the relationships are not faulted per
    /// row.
    init(
        work: CDWorkModel,
        context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date()
    ) {
        let workCheckIns = checkIns ?? ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
        let workNotes = notes ?? ((work.unifiedNotes?.allObjects as? [CDNote]) ?? [])

        let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(
            for: work,
            checkIns: workCheckIns,
            notes: workNotes
        )

        self.init(
            status: work.status,
            dueAt: work.dueAt,
            restingUntil: work.restingUntil,
            scheduledCheckInDates: workCheckIns
                .filter { $0.status == .scheduled }
                .compactMap(\.date),
            schoolDaysSinceLastTouch: SchoolCalendarService.shared.schoolDaysSinceCreation(
                createdAt: lastTouch,
                asOf: now,
                using: context
            )
        )
    }
}

// MARK: - Presentations

extension PresentationTriageInput {
    /// Reads one presentation into the values the rule needs.
    ///
    /// `unresolvedFollowUpIDs` is the set of `CDLessonAssignment` ids that have
    /// at least one `CDLessonPresentation` row with an open follow-up. Build it
    /// once per list with `LessonsAndWorkTriage.unresolvedFollowUpAssignmentIDs`
    /// rather than querying per row.
    init(assignment: CDLessonAssignment, unresolvedFollowUpIDs: Set<UUID>) {
        self.init(
            state: assignment.state,
            scheduledFor: assignment.scheduledFor,
            hasUnresolvedFollowUp: assignment.id.map(unresolvedFollowUpIDs.contains) ?? false
        )
    }
}

// MARK: - Managed-object entry points

extension LessonsAndWorkTriage {

    /// Places one work item straight from Core Data.
    static func bucket(
        for work: CDWorkModel,
        context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date()
    ) -> TriageBucket {
        let input = WorkTriageInput(
            work: work,
            context: context,
            checkIns: checkIns,
            notes: notes,
            asOf: now
        )
        return bucket(for: input, asOf: now)
    }

    /// Places one presentation straight from Core Data.
    static func bucket(
        for assignment: CDLessonAssignment,
        unresolvedFollowUpIDs: Set<UUID>
    ) -> TriageBucket {
        bucket(for: PresentationTriageInput(
            assignment: assignment,
            unresolvedFollowUpIDs: unresolvedFollowUpIDs
        ))
    }

    /// The assignment ids that still carry an unresolved follow-up.
    ///
    /// A presentation is given to a group, so one assignment fans out to one
    /// `CDLessonPresentation` row per child. The assignment needs the guide
    /// while *any* of those rows is still open.
    static func unresolvedFollowUpAssignmentIDs(
        from rows: [CDLessonPresentation]
    ) -> Set<UUID> {
        Set(
            rows
                .filter(\.hasOpenFollowUp)
                .compactMap { $0.presentationID.flatMap(UUID.init(uuidString:)) }
        )
    }

    /// Fetches the open follow-up rows and reduces them to assignment ids.
    /// Use the array overload when the caller already has the rows on hand.
    static func unresolvedFollowUpAssignmentIDs(
        in context: NSManagedObjectContext
    ) -> Set<UUID> {
        let request: NSFetchRequest<CDLessonPresentation> = NSFetchRequest(entityName: "LessonPresentation")
        request.predicate = NSPredicate(format: "followUpActionRaw != nil AND followUpResolvedAt == nil")
        return unresolvedFollowUpAssignmentIDs(from: context.safeFetch(request))
    }
}
