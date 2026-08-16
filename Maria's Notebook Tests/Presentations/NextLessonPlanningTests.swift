import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Next Lesson Planning Requires an Explicit Choice")
@MainActor
struct NextLessonPlanningTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let student: CDStudent
        let currentLesson: CDLesson
        let nextLesson: CDLesson

        var studentID: UUID { student.id! }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let currentLesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Golden Beads",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        currentLesson.orderInSequence = 1

        let nextLesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Large Number Cards",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        nextLesson.orderInSequence = 2

        _ = try #require(student.id)
        _ = try #require(currentLesson.id)
        _ = try #require(nextLesson.id)
        return Fixture(
            context: context,
            student: student,
            currentLesson: currentLesson,
            nextLesson: nextLesson
        )
    }

    private func assignments(in context: NSManagedObjectContext) throws -> [CDLessonAssignment] {
        try context.fetch(CDFetchRequest(CDLessonAssignment.self))
    }

    @Test("The default leaves the next lesson unchanged")
    func noChangeDefaultDoesNotCreateAnything() throws {
        let fixture = try makeFixture()
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])
        viewModel.nextLesson = fixture.nextLesson

        #expect(viewModel.nextLessonAction == .noChange)

        viewModel.executeNextLessonAction(
            studentIDs: [fixture.studentID],
            allStudents: [fixture.student],
            allLessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [],
            viewContext: fixture.context
        )

        #expect(try assignments(in: fixture.context).isEmpty)
    }

    @Test("Looking up an existing plan still defaults to no change")
    func existingPlanIsNotChangedWithoutAChoice() throws {
        let fixture = try makeFixture()
        let scheduledDate = AppCalendar.startOfDay(Date().addingTimeInterval(3 * 86_400))
        let existing = PresentationFactory.makeScheduled(
            lessonID: try #require(fixture.nextLesson.id),
            studentIDs: [fixture.studentID],
            scheduledFor: scheduledDate,
            context: fixture.context
        )
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])
        viewModel.nextLessonAction = .inbox

        viewModel.resolveNextLesson(
            lessonID: try #require(fixture.currentLesson.id),
            studentIDs: [fixture.studentID],
            lessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [existing],
            context: fixture.context
        )

        #expect(viewModel.nextLessonAction == .noChange)
        #expect(viewModel.existingNextAssignment === existing)

        viewModel.executeNextLessonAction(
            studentIDs: [fixture.studentID],
            allStudents: [fixture.student],
            allLessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [existing],
            viewContext: fixture.context
        )

        #expect(existing.state == .scheduled)
        #expect(existing.scheduledFor == scheduledDate)
    }

    @Test("Choosing Add to Inbox creates a draft")
    func explicitInboxChoiceCreatesDraft() throws {
        let fixture = try makeFixture()
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])
        viewModel.nextLesson = fixture.nextLesson
        viewModel.nextLessonAction = .inbox

        viewModel.executeNextLessonAction(
            studentIDs: [fixture.studentID],
            allStudents: [fixture.student],
            allLessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [],
            viewContext: fixture.context
        )

        let created = try #require(assignments(in: fixture.context).first)
        #expect(created.lessonIDUUID == fixture.nextLesson.id)
        #expect(created.state == .draft)
        #expect(created.scheduledFor == nil)
    }

    @Test("Choosing Add to Inbox removes an existing schedule cleanly")
    func explicitInboxChoiceUnschedulesExistingAssignment() throws {
        let fixture = try makeFixture()
        let scheduledDate = AppCalendar.startOfDay(Date().addingTimeInterval(3 * 86_400))
        let existing = PresentationFactory.makeScheduled(
            lessonID: try #require(fixture.nextLesson.id),
            studentIDs: [fixture.studentID],
            scheduledFor: scheduledDate,
            context: fixture.context
        )
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])
        viewModel.nextLesson = fixture.nextLesson
        viewModel.existingNextAssignment = existing
        viewModel.nextLessonAction = .inbox

        viewModel.executeNextLessonAction(
            studentIDs: [fixture.studentID],
            allStudents: [fixture.student],
            allLessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [existing],
            viewContext: fixture.context
        )

        #expect(existing.state == .draft)
        #expect(existing.scheduledFor == nil)
        #expect(existing.scheduledForDay == Date.distantPast)
    }

    @Test("Choosing Schedule creates a dated plan")
    func explicitScheduleChoiceCreatesScheduledAssignment() throws {
        let fixture = try makeFixture()
        let scheduleDate = AppCalendar.startOfDay(Date().addingTimeInterval(4 * 86_400))
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])
        viewModel.nextLesson = fixture.nextLesson
        viewModel.nextLessonAction = .schedule
        viewModel.nextLessonScheduleDate = scheduleDate

        viewModel.executeNextLessonAction(
            studentIDs: [fixture.studentID],
            allStudents: [fixture.student],
            allLessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [],
            viewContext: fixture.context
        )

        let created = try #require(assignments(in: fixture.context).first)
        #expect(created.lessonIDUUID == fixture.nextLesson.id)
        #expect(created.state == .scheduled)
        #expect(created.scheduledFor == scheduleDate)
        #expect(created.scheduledForDay == scheduleDate)
    }

    @Test("Choosing Schedule updates every date field on an existing inbox item")
    func explicitScheduleChoiceUpdatesExistingAssignment() throws {
        let fixture = try makeFixture()
        let existing = PresentationFactory.makeDraft(
            lessonID: try #require(fixture.nextLesson.id),
            studentIDs: [fixture.studentID],
            context: fixture.context
        )
        let oldModifiedAt = Date(timeIntervalSinceReferenceDate: 100)
        existing.modifiedAt = oldModifiedAt
        let scheduleDate = AppCalendar.startOfDay(Date().addingTimeInterval(5 * 86_400))
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])
        viewModel.nextLesson = fixture.nextLesson
        viewModel.existingNextAssignment = existing
        viewModel.nextLessonAction = .schedule
        viewModel.nextLessonScheduleDate = scheduleDate

        viewModel.executeNextLessonAction(
            studentIDs: [fixture.studentID],
            allStudents: [fixture.student],
            allLessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [existing],
            viewContext: fixture.context
        )

        #expect(existing.state == .scheduled)
        #expect(existing.scheduledFor == scheduleDate)
        #expect(existing.scheduledForDay == scheduleDate)
        #expect(existing.modifiedAt != oldModifiedAt)
    }

    @Test("An undated historical presentation is never reused as a future plan")
    func previouslyPresentedAssignmentIsNotAPlanningCandidate() throws {
        let fixture = try makeFixture()
        let historical = PresentationFactory.makePreviouslyPresented(
            lessonID: try #require(fixture.nextLesson.id),
            studentIDs: [fixture.studentID],
            context: fixture.context
        )
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])

        viewModel.resolveNextLesson(
            lessonID: try #require(fixture.currentLesson.id),
            studentIDs: [fixture.studentID],
            lessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [historical],
            context: fixture.context
        )

        #expect(viewModel.existingNextAssignment == nil)
        #expect(historical.isPresented)
        #expect(historical.presentedAt == nil)
    }

    @Test("Re-resolving the same lesson preserves an explicit choice")
    func repeatedResolutionPreservesChoice() throws {
        let fixture = try makeFixture()
        let viewModel = PostPresentationFormViewModel(students: [fixture.student])

        viewModel.resolveNextLesson(
            lessonID: try #require(fixture.currentLesson.id),
            studentIDs: [fixture.studentID],
            lessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [],
            context: fixture.context
        )
        viewModel.nextLessonAction = .schedule

        viewModel.resolveNextLesson(
            lessonID: try #require(fixture.currentLesson.id),
            studentIDs: [fixture.studentID],
            lessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignments: [],
            context: fixture.context
        )

        #expect(viewModel.nextLessonAction == .schedule)
    }

    @Test("Saving a presented lesson does not automatically create its successor")
    func ordinaryPresentationSaveDoesNotPlanNextLesson() throws {
        let fixture = try makeFixture()
        let assignment = PresentationFactory.makeDraft(
            lessonID: try #require(fixture.currentLesson.id),
            studentIDs: [fixture.studentID],
            context: fixture.context
        )
        assignment.lesson = fixture.currentLesson

        let saveCoordinator = SaveCoordinator()
        saveCoordinator.suppressAlerts = true
        let viewModel = PresentationDetailViewModel(
            lessonAssignment: assignment,
            viewContext: fixture.context,
            saveCoordinator: saveCoordinator
        )
        viewModel.isPresented = true
        viewModel.givenAt = Date()

        viewModel.save(
            studentsAll: [fixture.student],
            lessons: [fixture.currentLesson, fixture.nextLesson],
            lessonAssignmentsAll: [assignment],
            calendar: AppCalendar.shared
        )

        let savedAssignments = try assignments(in: fixture.context)
        #expect(savedAssignments.count == 1)
        #expect(savedAssignments.first?.lessonIDUUID == fixture.currentLesson.id)
        #expect(savedAssignments.first?.state == .presented)
        #expect(!savedAssignments.contains { $0.lessonIDUUID == fixture.nextLesson.id })
    }
}
