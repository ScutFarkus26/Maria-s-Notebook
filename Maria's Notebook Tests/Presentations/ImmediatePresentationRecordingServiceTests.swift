import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Immediate Presentation Recording")
@MainActor
final class ImmediatePresentationRecordingTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let students: [CDStudent]
        let assignment: CDLessonAssignment
        let scheduledDay: Date
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true

        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        lesson.area = ""
        lesson.sequence = ""
        let students = [
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada"),
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        ]
        let scheduledDay = AppCalendar.startOfDay(
            Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson,
            students: students,
            scheduledFor: scheduledDay,
            context: context
        )
        assignment.needsAnotherPresentation = true
        try context.save()

        return Fixture(
            context: context,
            coordinator: coordinator,
            lesson: lesson,
            students: students,
            assignment: assignment,
            scheduledDay: scheduledDay
        )
    }

    private func exactHistory(
        for assignment: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) throws -> [CDLessonPresentation] {
        let assignmentID = try #require(assignment.id)
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@",
            assignmentID.uuidString
        )
        return try context.fetch(request)
    }
}

extension ImmediatePresentationRecordingTests {
    @Test("A presentation without children is rejected before anything changes")
    func emptyRosterIsRejected() throws {
        let fixture = try makeFixture()
        fixture.assignment.studentIDs = []
        try fixture.context.save()

        do {
            _ = try ImmediatePresentationRecordingService.record(
                assignment: fixture.assignment,
                presentedOn: Date(),
                context: fixture.context,
                saveCoordinator: fixture.coordinator
            )
            Issue.record("An empty-roster presentation should not be recorded.")
        } catch let error as ImmediatePresentationRecordingService.RecordingError {
            guard case .invalidAssignment = error else {
                Issue.record("Expected invalidAssignment, received \(error)")
                return
            }
        }

        #expect(fixture.assignment.state == .scheduled)
        #expect(fixture.assignment.presentedAt == nil)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).isEmpty)
    }

    @Test("Just Presented records immediately without creating work or a next lesson")
    func recordsOnlyPresentationLifecycle() throws {
        let fixture = try makeFixture()
        let suppliedDate = Date(timeIntervalSinceReferenceDate: 801_234_567)
        let expectedDay = AppCalendar.startOfDay(suppliedDate)

        let token = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: suppliedDate,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        #expect(fixture.assignment.state == .presented)
        #expect(fixture.assignment.presentedAt == expectedDay)
        #expect(fixture.assignment.scheduledFor == nil)
        #expect(fixture.assignment.scheduledForDay == Date.distantPast)
        #expect(!fixture.assignment.needsAnotherPresentation)
        #expect(token.assignmentID == fixture.assignment.id)
        #expect(token.presentedDay == expectedDay)
        #expect(token.createdHistoryCount == 2)

        let history = try exactHistory(for: fixture.assignment, in: fixture.context)
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.presentedAt == expectedDay })
        #expect(history.allSatisfy { $0.followUpAction == .watchWork })
        #expect(history.allSatisfy { $0.hasOpenFollowUp })
        #expect(history.allSatisfy { $0.followUpReviewAt == nil })
        #expect(history.allSatisfy { $0.followUpResolvedAt == nil })

        let work = try fixture.context.fetch(CDFetchRequest(CDWorkModel.self))
        let assignments = try fixture.context.fetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(work.isEmpty)
        #expect(assignments.count == 1)
        #expect(fixture.students.allSatisfy { $0.nextLessonUUIDs.isEmpty })
        #expect(!fixture.context.hasChanges)
    }

    @Test("Just Presented refreshes an already-presented assignment and Undo restores it")
    func recordsAlreadyPresentedAssignmentAndUndoes() throws {
        let fixture = try makeFixture()
        fixture.assignment.state = .presented
        fixture.assignment.presentedAt = nil
        try fixture.context.save()

        let suppliedDate = Date(timeIntervalSinceReferenceDate: 801_234_567)
        let expectedDay = AppCalendar.startOfDay(suppliedDate)
        let token = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: suppliedDate,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        #expect(fixture.assignment.state == .presented)
        #expect(fixture.assignment.presentedAt == expectedDay)
        #expect(fixture.assignment.scheduledFor == nil)
        #expect(fixture.assignment.scheduledForDay == Date.distantPast)
        #expect(!fixture.assignment.needsAnotherPresentation)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).count == 2)

        try ImmediatePresentationRecordingService.undo(
            token,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        #expect(fixture.assignment.state == .presented)
        #expect(fixture.assignment.presentedAt == nil)
        #expect(fixture.assignment.scheduledFor == fixture.scheduledDay)
        #expect(fixture.assignment.scheduledForDay == AppCalendar.startOfDay(fixture.scheduledDay))
        #expect(fixture.assignment.needsAnotherPresentation)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test("Undo restores the assignment state, date, schedule, and follow-up flag")
    func undoRestoresAssignment() throws {
        let fixture = try makeFixture()
        let token = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: Date(timeIntervalSinceReferenceDate: 801_234_567),
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        try ImmediatePresentationRecordingService.undo(
            token,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        #expect(fixture.assignment.state == .scheduled)
        #expect(fixture.assignment.presentedAt == nil)
        #expect(fixture.assignment.scheduledFor == fixture.scheduledDay)
        #expect(fixture.assignment.scheduledForDay == AppCalendar.startOfDay(fixture.scheduledDay))
        #expect(fixture.assignment.needsAnotherPresentation)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test("Track enrollment is recorded and exactly restored by Undo")
    func trackEnrollmentFollowsImmediatePresentation() throws {
        let fixture = try makeFixture()
        fixture.lesson.area = "Mathematics"
        fixture.lesson.sequence = "Decimal System"
        let track = try SequenceTrackService.getOrCreateTrack(
            area: fixture.lesson.area,
            sequence: fixture.lesson.sequence,
            context: fixture.context
        )
        let firstStudent = try #require(fixture.students.first)
        let firstStudentID = try #require(firstStudent.id)
        let existingEnrollment = CDStudentTrackEnrollmentEntity(context: fixture.context)
        existingEnrollment.studentID = firstStudentID.uuidString
        existingEnrollment.trackID = try #require(track.id).uuidString
        existingEnrollment.isActive = false
        existingEnrollment.startedAt = nil
        existingEnrollment.track = track
        existingEnrollment.student = firstStudent
        try fixture.context.save()

        let token = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: Date(timeIntervalSinceReferenceDate: 801_234_567),
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        let enrollmentRequest = CDFetchRequest(CDStudentTrackEnrollmentEntity.self)
        let recordedEnrollments = try fixture.context.fetch(enrollmentRequest)
        #expect(recordedEnrollments.count == 2)
        #expect(recordedEnrollments.allSatisfy { $0.isActive })

        try ImmediatePresentationRecordingService.undo(
            token,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        let restoredEnrollments = try fixture.context.fetch(enrollmentRequest)
        #expect(restoredEnrollments.count == 1)
        #expect(restoredEnrollments.first?.id == existingEnrollment.id)
        #expect(restoredEnrollments.first?.isActive == false)
        #expect(restoredEnrollments.first?.startedAt == nil)
    }

    @Test("Undo preserves older and unrelated presentation history")
    func undoDeletesOnlyRowsCreatedByRecord() throws {
        let fixture = try makeFixture()
        let assignmentID = try #require(fixture.assignment.id)
        let lessonID = try #require(fixture.lesson.id)
        let firstStudentID = try #require(fixture.students.first?.id)
        let oldObservationDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

        let existing = CDLessonPresentation(context: fixture.context)
        existing.presentationID = assignmentID.uuidString
        existing.lessonID = lessonID.uuidString
        existing.studentID = firstStudentID.uuidString
        existing.state = .proficient
        existing.presentedAt = oldObservationDate
        existing.lastObservedAt = oldObservationDate

        let unrelated = CDLessonPresentation(context: fixture.context)
        unrelated.presentationID = UUID().uuidString
        unrelated.lessonID = lessonID.uuidString
        unrelated.studentID = firstStudentID.uuidString
        unrelated.state = .proficient
        unrelated.presentedAt = oldObservationDate
        unrelated.lastObservedAt = oldObservationDate
        let unrelatedID = try #require(unrelated.id)
        try fixture.context.save()

        let suppliedDate = Date(timeIntervalSinceReferenceDate: 801_234_567)
        let expectedDay = AppCalendar.startOfDay(suppliedDate)
        let token = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: suppliedDate,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        #expect(token.createdHistoryCount == 1)
        #expect(existing.lastObservedAt == expectedDay)
        #expect(existing.followUpAction == .watchWork)
        #expect(existing.hasOpenFollowUp)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).count == 2)

        try ImmediatePresentationRecordingService.undo(
            token,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        let remainingExact = try exactHistory(for: fixture.assignment, in: fixture.context)
        #expect(remainingExact.count == 1)
        #expect(remainingExact.first?.id == existing.id)
        #expect(remainingExact.first?.state == .proficient)
        #expect(remainingExact.first?.lastObservedAt == oldObservationDate)
        #expect(remainingExact.first?.followUpActionRaw == nil)
        #expect(remainingExact.first?.followUpUpdatedAt == nil)
        #expect(remainingExact.first?.followUpResolvedAt == nil)

        let unrelatedRequest = CDFetchRequest(CDLessonPresentation.self)
        unrelatedRequest.predicate = NSPredicate(format: "id == %@", unrelatedID as CVarArg)
        #expect(try fixture.context.fetch(unrelatedRequest).count == 1)
    }

    @Test("A save failure restores the pre-record in-memory state")
    func failedRecordRestoresState() throws {
        let fixture = try makeFixture()
        let invalidUnrelatedStudent = CDStudent(context: fixture.context)
        invalidUnrelatedStudent.setValue(nil, forKey: "firstName")

        do {
            _ = try ImmediatePresentationRecordingService.record(
                assignment: fixture.assignment,
                presentedOn: Date(timeIntervalSinceReferenceDate: 801_234_567),
                context: fixture.context,
                saveCoordinator: fixture.coordinator
            )
            Issue.record("Recording should fail when the context cannot save")
        } catch let error as ImmediatePresentationRecordingService.RecordingError {
            guard case .saveFailed = error else {
                Issue.record("Expected saveFailed, received \(error)")
                return
            }
        }

        #expect(fixture.assignment.state == .scheduled)
        #expect(fixture.assignment.presentedAt == nil)
        #expect(fixture.assignment.scheduledFor == fixture.scheduledDay)
        #expect(fixture.assignment.scheduledForDay == AppCalendar.startOfDay(fixture.scheduledDay))
        #expect(fixture.assignment.needsAnotherPresentation)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).isEmpty)
        #expect(invalidUnrelatedStudent.isInserted)
        #expect(invalidUnrelatedStudent.value(forKey: "firstName") == nil)
    }

    @Test("A failed Undo leaves the recorded presentation intact")
    func failedUndoRestoresRecordedState() throws {
        let fixture = try makeFixture()
        let suppliedDate = Date(timeIntervalSinceReferenceDate: 801_234_567)
        let expectedDay = AppCalendar.startOfDay(suppliedDate)
        let token = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: suppliedDate,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        let invalidUnrelatedStudent = CDStudent(context: fixture.context)
        invalidUnrelatedStudent.setValue(nil, forKey: "firstName")

        do {
            try ImmediatePresentationRecordingService.undo(
                token,
                context: fixture.context,
                saveCoordinator: fixture.coordinator
            )
            Issue.record("Undo should fail when the context cannot save")
        } catch let error as ImmediatePresentationRecordingService.RecordingError {
            guard case .undoSaveFailed = error else {
                Issue.record("Expected undoSaveFailed, received \(error)")
                return
            }
        }

        #expect(fixture.assignment.state == .presented)
        #expect(fixture.assignment.presentedAt == expectedDay)
        #expect(!fixture.assignment.needsAnotherPresentation)
        #expect(try exactHistory(for: fixture.assignment, in: fixture.context).count == 2)
        #expect(invalidUnrelatedStudent.isInserted)
    }
}
