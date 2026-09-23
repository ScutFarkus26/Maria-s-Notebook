import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the Works Agenda's cheaper rebuild path to the old one.
///
/// The partition used to triage every `CDLessonAssignment` in the table; it now
/// fetches only the rows that can land outside `.done`. The workspace lists
/// (attention, scheduled, to schedule) must come out identical.
@MainActor
@Suite("Works Agenda scoped rebuild")
struct WorksAgendaScopedRebuildTests {

    private func seedAssignment(
        in context: NSManagedObjectContext,
        stateRaw: String,
        scheduledFor: Date? = nil
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.stateRaw = stateRaw
        assignment.scheduledFor = scheduledFor
        return assignment
    }

    private func ids(_ split: TriageSplit<CDLessonAssignment>, _ bucket: TriageBucket) -> Set<UUID> {
        Set(split[bucket].compactMap(\.id))
    }

    private func assertSameWorkspaceLists(in context: NSManagedObjectContext) throws {
        let unresolved = LessonsAndWorkTriage.unresolvedFollowUpAssignmentIDs(in: context)
        let everything: [CDLessonAssignment] = context.safeFetch(NSFetchRequest(entityName: "LessonAssignment"))
        let scoped = LessonsAndWorkPartition.workspaceAssignments(in: context, unresolvedFollowUpIDs: unresolved)

        let old = LessonsAndWorkPartition(
            openWork: [], assignments: everything, unresolvedFollowUpIDs: unresolved, context: context
        )
        let new = LessonsAndWorkPartition(
            openWork: [], assignments: scoped, unresolvedFollowUpIDs: unresolved, context: context
        )
        for bucket in TriageBucket.workspaceCases {
            #expect(ids(new.presentations, bucket) == ids(old.presentations, bucket), "bucket \(bucket.rawValue) differs")
            #expect(new.presentations[bucket].count == old.presentations[bucket].count)
        }
        // Only `.done` rows are left out.
        #expect(new.presentations.done.isEmpty)
    }

    @Test("Scoped assignment fetch yields the same workspace lists, saved and unsaved")
    func scopedFetchMatchesWholeTable() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let day = Date(timeIntervalSince1970: 1_800_000_000)

        let draft = seedAssignment(in: context, stateRaw: LessonAssignmentState.draft.rawValue)
        let scheduled = seedAssignment(in: context, stateRaw: "scheduled", scheduledFor: day)
        let draftWithDay = seedAssignment(in: context, stateRaw: "draft", scheduledFor: day)
        let scheduledNoDay = seedAssignment(in: context, stateRaw: "scheduled")
        let unknown = seedAssignment(in: context, stateRaw: "bogus")
        let givenDone = seedAssignment(in: context, stateRaw: "presented")
        let givenOpen = seedAssignment(in: context, stateRaw: "presented")
        let givenResolved = seedAssignment(in: context, stateRaw: "presented")

        let openRow = CDLessonPresentation(context: context)
        openRow.presentationID = givenOpen.id?.uuidString
        openRow.followUpActionRaw = "checkIn"
        let resolvedRow = CDLessonPresentation(context: context)
        resolvedRow.presentationID = givenResolved.id?.uuidString
        resolvedRow.followUpActionRaw = "checkIn"
        resolvedRow.followUpResolvedAt = day

        // Unsaved: the scoped fetch must still see pending inserts.
        try assertSameWorkspaceLists(in: context)

        #expect(CoreDataTestHelpers.save(context))
        try assertSameWorkspaceLists(in: context)

        // Unsaved updates that move rows in and out of `.done`.
        givenDone.stateRaw = "draft"
        draft.stateRaw = "presented"
        try assertSameWorkspaceLists(in: context)

        let unresolved = LessonsAndWorkTriage.unresolvedFollowUpAssignmentIDs(in: context)
        let scopedIDs = Set(
            LessonsAndWorkPartition.workspaceAssignments(in: context, unresolvedFollowUpIDs: unresolved)
                .compactMap(\.id)
        )
        let expected = Set([scheduled, draftWithDay, scheduledNoDay, unknown, givenDone, givenOpen].compactMap(\.id))
        #expect(scopedIDs == expected)
    }

    // MARK: - Save gate

    @Test("Saves of unrelated entities do not refresh the agenda; relevant ones do")
    func saveGate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let attendance = CoreDataTestHelpers.seedAttendance(in: context)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let checkIn = CDWorkCheckIn(context: context)
        let note = CoreDataTestHelpers.seedNote(in: context)
        let assignment = CDLessonAssignment(context: context)

        #expect(WorksAgendaView.saveTouchesAgenda([NSInsertedObjectsKey: Set<NSManagedObject>([attendance])]) == false)
        #expect(WorksAgendaView.saveTouchesAgenda([NSUpdatedObjectsKey: Set<NSManagedObject>([work])]) == true)
        #expect(WorksAgendaView.saveTouchesAgenda([NSDeletedObjectsKey: Set<NSManagedObject>([checkIn])]) == true)
        #expect(WorksAgendaView.saveTouchesAgenda([NSUpdatedObjectsKey: Set<NSManagedObject>([note])]) == true)
        #expect(WorksAgendaView.saveTouchesAgenda([
            NSInsertedObjectsKey: Set<NSManagedObject>([attendance]),
            NSUpdatedObjectsKey: Set<NSManagedObject>([assignment])
        ]) == true)
        // Unknown shapes fail open, as the unscoped listener did.
        #expect(WorksAgendaView.saveTouchesAgenda(nil) == true)
        #expect(WorksAgendaView.saveTouchesAgenda([:]) == true)
        #expect(WorksAgendaView.saveTouchesAgenda([NSInvalidatedAllObjectsKey: [NSManagedObjectID]()]) == true)
    }
}
