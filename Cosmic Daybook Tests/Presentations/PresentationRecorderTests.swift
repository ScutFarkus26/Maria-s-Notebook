import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Presentation Recorder and one-click Presented")
@MainActor
struct PresentationRecorderTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let present: CDStudent
        let absent: CDStudent
        let assignment: CDLessonAssignment
        let today: Date
    }

    private func makeFixture(requiresPractice: Bool) throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Math", sequence: "Operations"
        )
        lesson.practiceOverride = requiresPractice ? .yes : .no
        lesson.confirmationOverride = .no
        let present = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let absent = CoreDataTestHelpers.seedStudent(in: context, firstName: "Theo")
        let today = AppCalendar.startOfDay(Date())
        let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: try #require(absent.id), date: today)
        record.status = .absent
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [present, absent], scheduledFor: today, context: context
        )
        try context.save()
        return Fixture(
            context: context, coordinator: coordinator, lesson: lesson,
            present: present, absent: absent, assignment: assignment, today: today
        )
    }

    private func plans(for lesson: CDLesson, in context: NSManagedObjectContext) throws -> [CDLessonAssignment] {
        let lessonID = try #require(lesson.id)
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        return context.safeFetch(request)
    }

    @Test("An absent child stays on a plan of her own; only the others are recorded")
    func absentChildStaysOnPlan() throws {
        let fixture = try makeFixture(requiresPractice: false)
        let presentID = try #require(fixture.present.id)
        let absentID = try #require(fixture.absent.id)
        let absent = PresentationRecorder.absentStudentIDs(
            on: fixture.today, among: [presentID, absentID], context: fixture.context
        )
        #expect(absent == [absentID])

        let result = try PresentationRecorder.record(
            fixture.assignment, presentIDs: [presentID], on: fixture.today,
            context: fixture.context, saveCoordinator: fixture.coordinator
        )
        #expect(result.keptOnPlan == [absentID])
        #expect(fixture.assignment.isPresented)
        #expect(fixture.assignment.resolvedStudentIDs == [presentID])

        let presentationID = try #require(fixture.assignment.id)
        let rows = PresentationFollowUpService.rows(for: presentationID, in: fixture.context)
        #expect(rows.map(\.studentID) == [presentID.uuidString])

        let waiting = try plans(for: fixture.lesson, in: fixture.context).filter { !$0.isPresented }
        #expect(waiting.count == 1)
        #expect(waiting.first?.resolvedStudentIDs == [absentID])
    }

    @Test("Nobody ticked is refused before anything is written")
    func nobodyPresentIsRefused() throws {
        let fixture = try makeFixture(requiresPractice: false)
        #expect(throws: PresentationRecorder.RecordError.self) {
            try PresentationRecorder.record(
                fixture.assignment, presentIDs: [], on: fixture.today,
                context: fixture.context, saveCoordinator: fixture.coordinator
            )
        }
        #expect(!fixture.assignment.isPresented)
        #expect(fixture.assignment.resolvedStudentIDs.count == 2)
    }

    @Test("One click follows the lesson's practice rule, and Undo takes all of it back")
    func quickRecordAndUndo() throws {
        let fixture = try makeFixture(requiresPractice: true)
        let presentID = try #require(fixture.present.id)
        let receipt = try PresentationQuickRecord.record(
            fixture.assignment, lessons: [fixture.lesson],
            context: fixture.context, saveCoordinator: fixture.coordinator, today: fixture.today
        )
        #expect(receipt.decision == .practice)
        #expect(receipt.presentIDs == [presentID])
        #expect(receipt.createdWorkIDs.count == 1)
        #expect(fixture.assignment.isPresented)

        try PresentationQuickRecord.undo(receipt, context: fixture.context, saveCoordinator: fixture.coordinator)
        #expect(!fixture.assignment.isPresented)
        let presentationID = try #require(fixture.assignment.id)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        #expect(fixture.context.safeFetch(request).isEmpty)
        #expect(PresentationFollowUpService.rows(for: presentationID, in: fixture.context).isEmpty)
        // The absent child is back on this plan, and the plan made for her is gone.
        let absentID = try #require(fixture.absent.id)
        #expect(Set(fixture.assignment.resolvedStudentIDs) == [presentID, absentID])
        #expect(try plans(for: fixture.lesson, in: fixture.context).count == 1)
    }

    @Test("Undo puts the child who wasn't there back, with her year-plan entry")
    func undoRestoresAbsentChild() throws {
        let fixture = try makeFixture(requiresPractice: false)
        let presentID = try #require(fixture.present.id)
        let absentID = try #require(fixture.absent.id)
        let entry = CDYearPlanEntry(context: fixture.context)
        entry.studentID = absentID.uuidString
        entry.lessonID = fixture.assignment.lessonID
        entry.status = .promoted
        entry.promotedAssignmentID = fixture.assignment.id?.uuidString
        try fixture.context.save()

        let result = try PresentationRecorder.record(
            fixture.assignment, presentIDs: [presentID], on: fixture.today,
            context: fixture.context, saveCoordinator: fixture.coordinator
        )
        let madePlan = try #require(
            try plans(for: fixture.lesson, in: fixture.context).first { $0 !== fixture.assignment }
        )
        #expect(entry.promotedAssignmentID == madePlan.id?.uuidString)

        try ImmediatePresentationRecordingService.undo(
            result.undoToken, context: fixture.context, saveCoordinator: fixture.coordinator
        )
        #expect(!fixture.assignment.isPresented)
        #expect(Set(fixture.assignment.resolvedStudentIDs) == [presentID, absentID])
        #expect(try plans(for: fixture.lesson, in: fixture.context) == [fixture.assignment])
        #expect(entry.status == .promoted)
        #expect(entry.promotedAssignmentID == fixture.assignment.id?.uuidString)
    }

    @Test("Without a practice rule, one click records and keeps watching")
    func quickRecordKeepsWatching() throws {
        let fixture = try makeFixture(requiresPractice: false)
        let receipt = try PresentationQuickRecord.record(
            fixture.assignment, lessons: [fixture.lesson],
            context: fixture.context, saveCoordinator: fixture.coordinator, today: fixture.today
        )
        #expect(receipt.decision == .continueObserving)
        #expect(receipt.createdWorkIDs.isEmpty)
        let names = [
            try #require(fixture.present.id): "Maya S",
            try #require(fixture.absent.id): "Theo S"
        ]
        let message = PresentationQuickRecord.message(for: receipt, lessonName: "Stamp Game", names: names)
        #expect(message == "Stamp Game recorded for Maya S. Theo S was absent and stays on the plan.")
    }
}
