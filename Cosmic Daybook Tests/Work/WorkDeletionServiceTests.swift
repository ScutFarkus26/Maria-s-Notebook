import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The case that matters most is the first one: on a shared row the child being
// removed can be the owner, and a literal "delete the row she owns" would take
// the other child with her. Removal of an owner must be a self-participant
// delete plus promotion of a remaining participant, never a row delete.

@Suite("Work Deletion Service")
@MainActor
struct WorkDeletionServiceTests {

    // MARK: - Fixtures

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    /// One row carrying several children, `owner` in `studentID`.
    @discardableResult
    private func seedSharedRow(
        in context: NSManagedObjectContext, owner: UUID, passengers: [UUID],
        lessonID: UUID = UUID(), title: String = "Commutative law follow-up"
    ) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: title, studentID: owner, lessonID: lessonID
        )
        work.kind = .followUpAssignment
        for studentID in [owner] + passengers {
            addParticipant(studentID, to: work, in: context)
        }
        return work
    }

    /// A fan-out group: one row per child, each naming every peer.
    private func seedLinkedCopies(
        in context: NSManagedObjectContext, studentIDs: [UUID], lessonID: UUID = UUID()
    ) -> [CDWorkModel] {
        let works = studentIDs.map { studentID -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Fundamental Needs Poster", studentID: studentID, lessonID: lessonID
            )
            work.kind = .followUpAssignment
            addParticipant(studentID, to: work, in: context)
            return work
        }
        for work in works {
            for other in works where other !== work {
                addParticipant(UUID(uuidString: other.studentID)!, to: work, in: context)
            }
        }
        return works
    }

    private func addParticipant(_ studentID: UUID, to work: CDWorkModel, in context: NSManagedObjectContext) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = studentID.uuidString
        participant.work = work
    }

    /// A deleted object reports `isDeleted == false` once the save lands, so
    /// absence is judged by the object having left its context.
    private func isGone(_ object: NSManagedObject) -> Bool {
        object.isDeleted || object.managedObjectContext == nil
    }

    private func participantIDs(of work: CDWorkModel) -> Set<String> {
        Set(((work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).map(\.studentID))
    }

    // MARK: - Removing an owner from a shared row

    @Test("removing the owner of a one-row shared group promotes the other child and keeps the row")
    func removingOwnerOfSharedRowPromotes() throws {
        let context = try makeContext()
        let ora = UUID()
        let naomi = UUID()
        let work = seedSharedRow(in: context, owner: ora, passengers: [naomi])
        let workID = try #require(work.id)
        CoreDataTestHelpers.save(context)

        let service = WorkDeletionService(context: context)
        let plan = try service.removalPlan(for: ora, from: work)
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].action == .promote(to: naomi))

        try service.remove(studentID: ora, from: work)

        let survivor = try #require(WorkRepository(context: context).fetchWorkModel(id: workID))
        #expect(!survivor.isDeleted)
        #expect(survivor.studentID == naomi.uuidString)
        #expect(participantIDs(of: survivor) == [naomi.uuidString])
        #expect(WorkGrouping.studentIDs(of: survivor) == [naomi])
    }

    @Test("removing a passenger drops only her participant row")
    func removingPassengerDropsHerRowOnly() throws {
        let context = try makeContext()
        let avital = UUID()
        let naomi = UUID()
        let work = seedSharedRow(in: context, owner: avital, passengers: [naomi])
        CoreDataTestHelpers.save(context)

        let service = WorkDeletionService(context: context)
        let plan = try service.removalPlan(for: naomi, from: work)
        #expect(plan.steps.map(\.action) == [.dropParticipant])

        try service.remove(studentID: naomi, from: work)

        #expect(work.studentID == avital.uuidString)
        #expect(participantIDs(of: work) == [avital.uuidString])
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).count == 1)
    }

    @Test("the last child on a row is refused, not silently escalated to a delete")
    func lastChildIsRefused() throws {
        let context = try makeContext()
        let only = UUID()
        let work = seedSharedRow(in: context, owner: only, passengers: [])
        CoreDataTestHelpers.save(context)

        let service = WorkDeletionService(context: context)
        #expect(throws: WorkDeletionService.ServiceError.wouldEmptyRow) {
            try service.removalPlan(for: only, from: work)
        }
        #expect(!work.isDeleted)
    }

    @Test("offered project work may be left with nobody on it")
    func projectWorkMayBeEmptied() throws {
        let context = try makeContext()
        let only = UUID()
        let work = seedSharedRow(in: context, owner: only, passengers: [])
        work.sourceContextType = .projectSession
        CoreDataTestHelpers.save(context)

        try WorkDeletionService(context: context).remove(studentID: only, from: work)
        #expect(!work.isDeleted)
        #expect(work.studentID.isEmpty)
        #expect(work.isOffered)
    }

    @Test("a child who is not on the work is refused")
    func strangerIsRefused() throws {
        let context = try makeContext()
        let work = seedSharedRow(in: context, owner: UUID(), passengers: [UUID()])
        CoreDataTestHelpers.save(context)

        #expect(throws: WorkDeletionService.ServiceError.studentNotOnWork) {
            try WorkDeletionService(context: context).removalPlan(for: UUID(), from: work)
        }
    }

    // MARK: - Linked copies

    @Test("removing the owner of a linked copy deletes her row and drops her from the siblings")
    func removingOwnerOfLinkedCopyDeletesHerRow() throws {
        let context = try makeContext()
        let leshem = UUID()
        let avigail = UUID()
        let works = seedLinkedCopies(in: context, studentIDs: [leshem, avigail])
        CoreDataTestHelpers.save(context)
        let leshemsRow = try #require(works.first { $0.studentID == leshem.uuidString })
        let avigailsRow = try #require(works.first { $0.studentID == avigail.uuidString })

        let service = WorkDeletionService(context: context)
        let plan = try service.removalPlan(for: leshem, from: avigailsRow)
        #expect(Set(plan.steps.map(\.action)) == [.deleteRow, .dropParticipant])

        try service.remove(studentID: leshem, from: avigailsRow)

        #expect(isGone(leshemsRow))
        #expect(!isGone(avigailsRow))
        #expect(avigailsRow.studentID == avigail.uuidString)
        #expect(participantIDs(of: avigailsRow) == [avigail.uuidString])
    }

    @Test("a passenger on one linked copy comes off that copy alone")
    func passengerOnOneCopyComesOffThatCopy() throws {
        // Sarah Zakon's shape: named on Avigail's copy, not on Leshem's, with
        // no row of her own.
        let context = try makeContext()
        let avigail = UUID()
        let leshem = UUID()
        let sarah = UUID()
        let works = seedLinkedCopies(in: context, studentIDs: [avigail, leshem])
        let avigailsRow = try #require(works.first { $0.studentID == avigail.uuidString })
        let leshemsRow = try #require(works.first { $0.studentID == leshem.uuidString })
        addParticipant(sarah, to: avigailsRow, in: context)
        CoreDataTestHelpers.save(context)

        let service = WorkDeletionService(context: context)
        let plan = try service.removalPlan(for: sarah, from: avigailsRow)
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].work === avigailsRow)
        #expect(plan.steps[0].action == .dropParticipant)

        try service.remove(studentID: sarah, from: avigailsRow)

        #expect(!isGone(avigailsRow))
        #expect(!isGone(leshemsRow))
        #expect(participantIDs(of: avigailsRow) == [avigail.uuidString, leshem.uuidString])
        #expect(participantIDs(of: leshemsRow) == [avigail.uuidString, leshem.uuidString])
        // The copies still name each other, so they still read as one group.
        #expect(WorkGrouping.group(containing: avigailsRow, in: context).shape == .linkedCopies(total: 2))
    }

    // MARK: - Completion history

    @Test("her completion records go with her; nobody else's are touched")
    func completionRecordsFollowHer() throws {
        let context = try makeContext()
        let owner = UUID()
        let passenger = UUID()
        let work = seedSharedRow(in: context, owner: owner, passengers: [passenger])
        let workID = try #require(work.id)
        try WorkCompletionService.markCompleted(workID: workID, studentID: passenger, in: context)
        try WorkCompletionService.markCompleted(workID: workID, studentID: owner, in: context)

        let service = WorkDeletionService(context: context)
        let plan = try service.removalPlan(for: passenger, from: work)
        #expect(plan.completionRecords.count == 1)

        try service.remove(studentID: passenger, from: work)

        #expect(try WorkCompletionService.records(for: workID, studentID: passenger, in: context).isEmpty)
        #expect(try WorkCompletionService.records(for: workID, studentID: owner, in: context).count == 1)
        #expect(work.participant(for: owner)?.completedAt == nil)
    }

    // MARK: - Cascade counting

    @Test("cascade counts check-ins reachable only through the workID string")
    func cascadeCountsStringKeyedCheckIns() throws {
        let context = try makeContext()
        let work = seedSharedRow(in: context, owner: UUID(), passengers: [])
        let workID = try #require(work.id)

        let attached = CDWorkCheckIn(context: context)
        attached.workID = workID.uuidString
        attached.work = work

        // The week-plan drop path: workID written, relationship not set.
        let detached = CDWorkCheckIn(context: context)
        detached.workID = workID.uuidString

        let unrelated = CDWorkCheckIn(context: context)
        unrelated.workID = UUID().uuidString
        CoreDataTestHelpers.save(context)

        let service = WorkDeletionService(context: context)
        #expect(service.cascade(for: work).checkIns == 2)
        #expect(WorkDeletionService.checkIns(of: work, in: context).count == 2)

        try service.delete([work])
        #expect(isGone(detached))
        #expect(isGone(attached))
        #expect(!isGone(unrelated))
    }

    @Test("cascade counts completion records, meeting reviews and scheduled meetings by string")
    func cascadeCountsStringKeyedRecords() throws {
        let context = try makeContext()
        let owner = UUID()
        let work = seedSharedRow(in: context, owner: owner, passengers: [])
        let workID = try #require(work.id)
        try WorkCompletionService.markCompleted(workID: workID, studentID: owner, in: context)
        let review = CDMeetingWorkReview(context: context)
        review.workID = workID.uuidString
        let meeting = CDScheduledMeeting(context: context)
        meeting.workID = workID.uuidString
        CoreDataTestHelpers.save(context)

        let service = WorkDeletionService(context: context)
        let cascade = service.cascade(for: work)
        #expect(cascade.completionRecords == 1)
        #expect(cascade.meetingReviews == 1)
        #expect(cascade.scheduledMeetings == 1)

        try service.delete([work])
        // Records only this work explains go with it; the meeting and its
        // review stand, the meeting losing only its anchor.
        #expect(try WorkCompletionService.records(for: workID, in: context).isEmpty)
        #expect(!isGone(review))
        #expect(!isGone(meeting))
        #expect(meeting.workID == nil)
    }

    // MARK: - Deleting a linked copy

    @Test("deleting one linked copy strips its owner from the copies that survive")
    func deleteStripsOwnerFromSurvivingCopies() throws {
        let context = try makeContext()
        let naomi = UUID()
        let ora = UUID()
        let works = seedLinkedCopies(in: context, studentIDs: [naomi, ora])
        CoreDataTestHelpers.save(context)
        let naomisRow = try #require(works.first { $0.studentID == naomi.uuidString })
        let orasRow = try #require(works.first { $0.studentID == ora.uuidString })

        try WorkDeletionService(context: context).delete([naomisRow])

        #expect(isGone(naomisRow))
        #expect(participantIDs(of: orasRow) == [ora.uuidString])
        #expect(WorkGrouping.group(containing: orasRow, in: context).shape == .single)
    }

    @Test("a failed save rolls the removal back")
    func failedSaveRollsBack() throws {
        let context = try makeContext()
        let owner = UUID()
        let passenger = UUID()
        let work = seedSharedRow(in: context, owner: owner, passengers: [passenger])
        CoreDataTestHelpers.save(context)

        #expect(throws: WorkDeletionService.ServiceError.saveFailed) {
            try WorkDeletionService(context: context).remove(studentID: passenger, from: work) { false }
        }
        #expect(participantIDs(of: work) == [owner.uuidString, passenger.uuidString])
    }
}
