import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, Group C. A presentation's per-child history
// rows (`CDLessonPresentation`) are what the year plan and the regive guard
// read as "given". Deleting a presentation, un-marking it, or taking a child
// off it left those rows behind, so the child still read as given. Year-plan
// entries promoted into a plan were likewise left pointing at a plan that no
// longer held them. Just Presented's Undo didn't put back the plans the
// recording trimmed, and a corrected given date never reached the rows.
@Suite("Stale given rows")
@MainActor
struct StaleGivenRowsTests {

    private struct Group {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let ada: CDStudent
        let ben: CDStudent
        let assignment: CDLessonAssignment
    }

    private let givenDay = AppCalendar.startOfDay(Date().addingTimeInterval(-86_400))

    private func daysFromNow(_ days: Double) -> Date {
        Date().addingTimeInterval(days * 86_400)
    }

    /// A lesson given yesterday to Ada and Ben on one presentation.
    private func makeGivenGroup() throws -> Group {
        let ctx = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Checkerboard")
        let ada = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ben")
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada, ben], scheduledFor: givenDay, context: ctx
        )
        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: givenDay, modelContext: ctx)
        #expect(CoreDataTestHelpers.save(ctx))
        return Group(context: ctx, lesson: lesson, ada: ada, ben: ben, assignment: assignment)
    }

    private func viewModel(for group: Group) -> PresentationDetailViewModel {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(
            lessonAssignment: group.assignment, viewContext: group.context, saveCoordinator: coordinator
        )
    }

    private func save(_ viewModel: PresentationDetailViewModel, _ group: Group) {
        viewModel.save(
            studentsAll: [group.ada, group.ben],
            lessons: [group.lesson],
            lessonAssignmentsAll: [group.assignment],
            calendar: AppCalendar.shared
        )
    }

    private func rows(
        for assignment: CDLessonAssignment, in ctx: NSManagedObjectContext
    ) throws -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@", try #require(assignment.id).uuidString
        )
        return ctx.safeFetch(request)
    }

    @discardableResult
    private func seedEntry(
        in ctx: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        promotedInto assignment: CDLessonAssignment
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: ctx)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = daysFromNow(3)
        entry.sequenceGroupKey = "Math::Checkerboard"
        entry.status = .promoted
        entry.promotedAssignmentID = assignment.id?.uuidString
        return entry
    }

    // MARK: - C8: delete, un-mark, remove a child

    @Test("Un-marking a given presentation takes its given rows with it")
    func unmarkingClearsRows() throws {
        let group = try makeGivenGroup()
        #expect(try rows(for: group.assignment, in: group.context).count == 2)

        let viewModel = viewModel(for: group)
        viewModel.isPresented = false
        viewModel.givenAt = nil
        viewModel.scheduledFor = daysFromNow(2)
        save(viewModel, group)

        #expect(!group.assignment.isPresented)
        #expect(try rows(for: group.assignment, in: group.context).isEmpty)
    }

    @Test("Taking a child off a given presentation clears her row and returns her entry to planned")
    func removingAChildClearsOnlyHerRow() throws {
        let group = try makeGivenGroup()
        let ctx = group.context
        let hers = seedEntry(in: ctx, student: group.ben, lesson: group.lesson, promotedInto: group.assignment)
        let his = seedEntry(in: ctx, student: group.ada, lesson: group.lesson, promotedInto: group.assignment)
        #expect(CoreDataTestHelpers.save(group.context))

        let viewModel = viewModel(for: group)
        viewModel.selectedStudentIDs = [try #require(group.ada.id)]
        save(viewModel, group)

        let remaining = try rows(for: group.assignment, in: group.context)
        #expect(remaining.map(\.studentID) == [try #require(group.ada.id).uuidString])
        #expect(hers.isPlanned)
        #expect(hers.promotedAssignmentID == nil)
        #expect(his.isPromoted)
    }

    @Test("Deleting a presentation deletes its given rows and returns entries promoted into it")
    func deletingClearsRowsAndEntries() async throws {
        let group = try makeGivenGroup()
        let entry = seedEntry(
            in: group.context, student: group.ada, lesson: group.lesson, promotedInto: group.assignment
        )
        #expect(CoreDataTestHelpers.save(group.context))

        viewModel(for: group).delete()
        for _ in 0..<200 where !group.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(group.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).isEmpty)
        #expect(group.context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).isEmpty)
        #expect(entry.isPlanned)
        #expect(entry.promotedAssignmentID == nil)
        #expect(!group.context.hasChanges)
    }

    // MARK: - C9: promoted entries follow the plan

    @Test("A child released from another plan keeps her entry, pointed at the presentation that answered it")
    func releasedEntryFollowsTheGivenPresentation() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Skip Counting")
        let early = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Maya")
        let other = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Toba")
        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [early, other], scheduledFor: daysFromNow(3), context: ctx
        )
        let hers = seedEntry(in: ctx, student: early, lesson: lesson, promotedInto: thursday)
        let today = PresentationFactory.makeDraft(lesson: lesson, students: [early], context: ctx)
        #expect(CoreDataTestHelpers.save(ctx))

        _ = try LifecycleService.recordPresentation(from: today, presentedAt: Date(), modelContext: ctx)

        #expect(thursday.studentIDs == [try #require(other.id).uuidString])
        #expect(hers.isPromoted)
        #expect(hers.promotedAssignmentID == today.id?.uuidString)
    }

    @Test("A departing child's entry promoted into a plan she comes off is skipped")
    func departureSkipsHerPromotedEntry() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Stamp Game")
        let leaving = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Baila")
        let staying = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Dalia")
        let shared = PresentationFactory.makeScheduled(
            lesson: lesson, students: [leaving, staying], scheduledFor: daysFromNow(3), context: ctx
        )
        let hers = seedEntry(in: ctx, student: leaving, lesson: lesson, promotedInto: shared)
        let classmates = seedEntry(in: ctx, student: staying, lesson: lesson, promotedInto: shared)
        #expect(CoreDataTestHelpers.save(ctx))

        let leavingID = try #require(leaving.id)
        StudentDeparturePlans.retract(
            studentID: leavingID, from: StudentDeparturePlans.futurePlans(for: leavingID, in: ctx), in: ctx
        )

        #expect(hers.status == .skipped)
        #expect(hers.promotedAssignmentID == nil)
        #expect(classmates.isPromoted)
    }

    @Test("A plan deleted at departure returns entries still pointing at it to planned")
    func departureDeleteReturnsStrandedEntries() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Stamp Game")
        let leaving = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Baila")
        let classmate = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Dalia")
        let solo = PresentationFactory.makeScheduled(
            lesson: lesson, students: [leaving], scheduledFor: daysFromNow(3), context: ctx
        )
        // An entry left pointing at this plan after its child was taken off by hand.
        let stranded = seedEntry(in: ctx, student: classmate, lesson: lesson, promotedInto: solo)
        #expect(CoreDataTestHelpers.save(ctx))

        let leavingID = try #require(leaving.id)
        StudentDeparturePlans.retract(studentID: leavingID, from: [solo], in: ctx)

        #expect(solo.isDeleted)
        #expect(stranded.isPlanned)
        #expect(stranded.promotedAssignmentID == nil)
    }

    // MARK: - C10: Just Presented's Undo puts released plans back

    @Test("Undo puts a child back on the plan the recording trimmed her from, and on a plan it discarded")
    func undoRestoresReleasedPlans() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Golden Beads")
        lesson.area = ""
        lesson.sequence = ""
        let maya = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Maya")
        let toba = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Toba")
        let lucy = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Lucy")
        let mayaID = try #require(maya.id).uuidString
        let tobaID = try #require(toba.id).uuidString
        let lucyID = try #require(lucy.id).uuidString

        // Thursday: Maya and Toba, Maya confirmed. Friday: Lucy alone.
        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya, toba], scheduledFor: daysFromNow(3), context: ctx
        )
        thursday.confirmedStudentIDs = [mayaID]
        let friday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [lucy], scheduledFor: daysFromNow(4), context: ctx
        )
        friday.notes = "Bring the bead cabinet."
        let fridayID = try #require(friday.id)
        let fridayScheduled = friday.scheduledFor
        let mayaEntry = seedEntry(in: ctx, student: maya, lesson: lesson, promotedInto: thursday)
        let lucyEntry = seedEntry(in: ctx, student: lucy, lesson: lesson, promotedInto: friday)
        let today = PresentationFactory.makeDraft(lesson: lesson, students: [maya, lucy], context: ctx)
        #expect(CoreDataTestHelpers.save(ctx))

        let token = try ImmediatePresentationRecordingService.record(
            assignment: today, presentedOn: Date(), context: ctx, saveCoordinator: coordinator
        )
        #expect(thursday.studentIDs == [tobaID])
        #expect(ctx.object(CDLessonAssignment.self, id: fridayID) == nil)

        try ImmediatePresentationRecordingService.undo(token, context: ctx, saveCoordinator: coordinator)

        #expect(Set(thursday.studentIDs) == [mayaID, tobaID])
        #expect(thursday.confirmedStudentIDs == [mayaID])
        let restored = try #require(ctx.object(CDLessonAssignment.self, id: fridayID))
        #expect(restored.studentIDs == [lucyID])
        #expect(restored.scheduledFor == fridayScheduled)
        #expect(restored.notes == "Bring the bead cabinet.")
        #expect(mayaEntry.isPromoted)
        #expect(mayaEntry.promotedAssignmentID == thursday.id?.uuidString)
        #expect(lucyEntry.isPromoted)
        #expect(lucyEntry.promotedAssignmentID == fridayID.uuidString)
        #expect(!ctx.hasChanges)
    }

    // MARK: - C11: a corrected date reaches the rows

    @Test("Correcting the given date moves every child's row to the new date")
    func correctedDateReachesRows() throws {
        let group = try makeGivenGroup()
        let corrected = AppCalendar.startOfDay(daysFromNow(-5))

        let viewModel = viewModel(for: group)
        viewModel.givenAt = corrected
        save(viewModel, group)

        let given = try rows(for: group.assignment, in: group.context)
        #expect(given.count == 2)
        #expect(given.allSatisfy { $0.presentedAt == corrected })
        #expect(group.assignment.presentedAt == corrected)
    }
}
