import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What Done writes for the next lesson when a child is marked Ready for next:
/// the Inbox, a day, or a day and a start time, as chosen on the sheet's
/// "Next lesson" row (docs/Plans/Plan - Next lesson row when presenting.md).
@Suite("Presentation Next Lesson Commit")
@MainActor
struct PresentationNextLessonCommitTests {
    private let calendar = AppCalendar.shared

    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let nextLesson: CDLesson
        let laterLesson: CDLesson
        let ada: UUID
        let ben: UUID
        let assignment: CDLessonAssignment
    }

    private var today: Date { AppCalendar.startOfDay(Date()) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// A recorded presentation of the first of three lessons in a sequence.
    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        func lesson(_ name: String, _ order: Int64) -> CDLesson {
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: name, area: "Language", sequence: "Grammar"
            )
            lesson.orderInSequence = order
            return lesson
        }
        let first = lesson("Nouns", 1)
        let second = lesson("Collective Nouns", 2)
        let third = lesson("Abstract Nouns", 3)
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let assignment = PresentationFactory.makeScheduled(
            lesson: first, students: [ada, ben], scheduledFor: today, context: context
        )
        try context.save()
        _ = try ImmediatePresentationRecordingService.record(
            assignment: assignment, presentedOn: today, context: context, saveCoordinator: coordinator
        )
        return Fixture(
            context: context, coordinator: coordinator, lesson: first, nextLesson: second, laterLesson: third,
            ada: try #require(ada.id), ben: try #require(ben.id), assignment: assignment
        )
    }

    @discardableResult
    private func commit(
        _ fixture: Fixture,
        ready: [UUID],
        place: PresentationNextLessonPlace?
    ) throws -> PresentationSessionCommit.Receipt {
        let decisions = Dictionary(uniqueKeysWithValues: ready.map { ($0, CaptureFollowUp.readyForNextLesson) })
        return try PresentationSessionCommit.apply(
            PresentationSessionCommit.Input(
                assignment: fixture.assignment,
                lesson: fixture.lesson,
                studentIDs: [fixture.ada, fixture.ben],
                groupNote: "",
                childNotes: [:],
                decisions: decisions,
                allDecisions: decisions,
                checkIn: .nextWorkCycle,
                lessons: [fixture.lesson, fixture.nextLesson, fixture.laterLesson],
                nextLessonPlace: place
            ),
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )
    }

    private func plans(for lesson: CDLesson, in fixture: Fixture) throws -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", try #require(lesson.id).uuidString)
        return fixture.context.safeFetch(request)
    }

    @discardableResult
    private func yearPlanEntry(
        for studentID: UUID, lesson: CDLesson, on date: Date, in fixture: Fixture
    ) throws -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: fixture.context)
        entry.studentID = studentID.uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.status = .planned
        entry.plannedDate = date
        try fixture.context.save()
        return entry
    }

    @Test("The Inbox keeps the plan unscheduled, even when the year plan has a day for it")
    func inboxStaysUnscheduled() throws {
        let fixture = try makeFixture()
        let entry = try yearPlanEntry(for: fixture.ada, lesson: fixture.nextLesson, on: day(7), in: fixture)

        let receipt = try commit(fixture, ready: [fixture.ada, fixture.ben], place: .inbox)
        #expect(receipt.nextLessonPlanned)
        #expect(receipt.nextLessonScheduledFor == nil)

        let plan = try #require(try plans(for: fixture.nextLesson, in: fixture).first)
        #expect(plan.scheduledFor == nil)
        #expect(Set(plan.resolvedStudentIDs) == [fixture.ada, fixture.ben])
        #expect(entry.status == .planned)
        #expect(entry.plannedDate == day(7))
    }

    @Test("With no choice the year plan's day still decides, as before")
    func noChoiceFollowsTheYearPlan() throws {
        let fixture = try makeFixture()
        let entry = try yearPlanEntry(for: fixture.ada, lesson: fixture.nextLesson, on: day(7), in: fixture)

        let receipt = try commit(fixture, ready: [fixture.ada], place: nil)
        let scheduled = try #require(receipt.nextLessonScheduledFor)
        #expect(calendar.isDate(scheduled, inSameDayAs: day(7)))
        #expect(entry.status == .promoted)

        // And with nothing on the year plan it waits in the Inbox.
        let other = try makeFixture()
        let plain = try commit(other, ready: [other.ada], place: nil)
        #expect(plain.nextLessonPlanned)
        #expect(plain.nextLessonScheduledFor == nil)
    }

    @Test("A day puts the plan at the end of that morning and moves the year plan with it")
    func dayIsScheduled() throws {
        let fixture = try makeFixture()
        let entry = try yearPlanEntry(for: fixture.ada, lesson: fixture.nextLesson, on: day(7), in: fixture)

        let place = PresentationNextLessonPlace(day: day(2))
        let receipt = try commit(fixture, ready: [fixture.ada, fixture.ben], place: place)

        let plan = try #require(try plans(for: fixture.nextLesson, in: fixture).first)
        let scheduled = try #require(plan.scheduledFor)
        #expect(receipt.nextLessonScheduledFor == scheduled)
        #expect(scheduled == DayHalfPlanner.slot(DayHalfPlanner.lastSlotRank, in: .morning, on: day(2)))
        #expect(DayHalfPlanner.isSetTime(scheduled) == false)
        #expect(plan.state == .scheduled)
        #expect(plan.scheduledForDay == day(2))

        #expect(entry.status == .promoted)
        #expect(entry.promotedAssignmentID == plan.id?.uuidString)
        #expect(entry.plannedDate == day(2))
    }

    @Test("A start time is kept to the minute, the base hours included")
    func dayAndTimeIsScheduled() throws {
        for (hour, minute) in [(10, 15), (9, 0), (14, 0)] {
            let fixture = try makeFixture()
            let place = PresentationNextLessonPlace(day: day(2)).settingTime(hour: hour, minute: minute)
            try commit(fixture, ready: [fixture.ada], place: place)

            let plan = try #require(try plans(for: fixture.nextLesson, in: fixture).first)
            let scheduled = try #require(plan.scheduledFor)
            #expect(calendar.isDate(scheduled, inSameDayAs: day(2)))
            #expect(ScheduledDateEdits.clockTime(of: scheduled) == LessonClockTime(hour: hour, minute: minute))
        }
    }

    @Test("A child already on a plan for it is not planned twice, and her plan is left alone")
    func alreadyPlannedChildIsSkipped() throws {
        let fixture = try makeFixture()
        let nextID = try #require(fixture.nextLesson.id)
        let waiting = PresentationFactory.makeDraft(
            lessonID: nextID, studentIDs: [fixture.ben], context: fixture.context
        )
        try fixture.context.save()

        try commit(fixture, ready: [fixture.ada, fixture.ben], place: PresentationNextLessonPlace(day: day(2)))
        let all = try plans(for: fixture.nextLesson, in: fixture)
        #expect(all.count == 2)
        #expect(waiting.scheduledFor == nil)
        let new = try #require(all.first { $0.objectID != waiting.objectID })
        #expect(new.resolvedStudentIDs == [fixture.ada])
        #expect(new.scheduledFor != nil)

        // Everyone already planned: nothing new is made.
        let again = try commit(fixture, ready: [fixture.ada, fixture.ben], place: .inbox)
        #expect(!again.nextLessonPlanned)
        #expect(try plans(for: fixture.nextLesson, in: fixture).count == 2)
    }

    @Test("Scheduling the next lesson lays nothing on the lessons after it")
    func nothingIsLaidOnLaterLessons() throws {
        let fixture = try makeFixture()
        try commit(fixture, ready: [fixture.ada, fixture.ben], place: PresentationNextLessonPlace(day: day(2)))

        #expect(try plans(for: fixture.laterLesson, in: fixture).isEmpty)
        #expect(fixture.context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).isEmpty)
    }
}
