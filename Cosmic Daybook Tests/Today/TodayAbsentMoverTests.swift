import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Today: move absent children to tomorrow")
@MainActor
struct TodayAbsentMoverTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let maya: CDStudent
        let theo: CDStudent
        let assignment: CDLessonAssignment
        let theoEntry: CDYearPlanEntry
        let today: Date
        let tomorrow: Date
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Math", sequence: "Operations"
        )
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let theo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Theo")
        let today = AppCalendar.startOfDay(Date())
        let tomorrow = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: today))
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya, theo], scheduledFor: today, context: context
        )
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(theo.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.sequenceGroupKey = "Math::Operations"
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(assignment.id).uuidString
        try context.save()
        return Fixture(
            context: context, coordinator: coordinator, lesson: lesson, maya: maya, theo: theo,
            assignment: assignment, theoEntry: entry, today: today, tomorrow: tomorrow
        )
    }

    private func plans(for lesson: CDLesson, in context: NSManagedObjectContext) throws -> [CDLessonAssignment] {
        let lessonID = try #require(lesson.id)
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        return context.safeFetch(request)
    }

    @Test("An absent child moves to a plan of her own tomorrow; the present one stays today")
    func absentChildMovesToTomorrow() throws {
        let fixture = try makeFixture()
        let mayaID = try #require(fixture.maya.id)
        let theoID = try #require(fixture.theo.id)

        let receipt = try #require(try TodayAbsentMover.moveAbsent(
            from: [fixture.assignment], absent: [theoID], to: fixture.tomorrow,
            context: fixture.context, saveCoordinator: fixture.coordinator
        ))
        #expect(receipt.movedStudentIDs == [theoID])
        #expect(fixture.context.hasChanges == false)

        #expect(fixture.assignment.resolvedStudentIDs == [mayaID])
        #expect(fixture.assignment.scheduledForDay == fixture.today)

        let moved = try plans(for: fixture.lesson, in: fixture.context).filter { $0 !== fixture.assignment }
        #expect(moved.count == 1)
        let plan = try #require(moved.first)
        #expect(plan.resolvedStudentIDs == [theoID])
        #expect(plan.scheduledForDay == fixture.tomorrow)
        #expect(plan.state == .scheduled)
        // Her year-plan entry follows her.
        #expect(fixture.theoEntry.promotedAssignmentID == plan.id?.uuidString)
    }

    @Test("Undo puts the child back on today's lesson and removes the plan it made")
    func undoRestoresEverything() throws {
        let fixture = try makeFixture()
        let mayaID = try #require(fixture.maya.id)
        let theoID = try #require(fixture.theo.id)
        let assignmentID = try #require(fixture.assignment.id).uuidString

        let receipt = try #require(try TodayAbsentMover.moveAbsent(
            from: [fixture.assignment], absent: [theoID], to: fixture.tomorrow,
            context: fixture.context, saveCoordinator: fixture.coordinator
        ))
        try TodayAbsentMover.undo(receipt, context: fixture.context, saveCoordinator: fixture.coordinator)

        #expect(fixture.context.hasChanges == false)
        #expect(Set(fixture.assignment.resolvedStudentIDs) == [mayaID, theoID])
        #expect(fixture.assignment.scheduledForDay == fixture.today)
        #expect(try plans(for: fixture.lesson, in: fixture.context) == [fixture.assignment])
        #expect(fixture.theoEntry.status == .promoted)
        #expect(fixture.theoEntry.promotedAssignmentID == assignmentID)
    }

    @Test("A lesson whose children are all absent moves whole, and Undo moves it back")
    func everyoneAbsentMovesTheLesson() throws {
        let fixture = try makeFixture()
        let mayaID = try #require(fixture.maya.id)
        let theoID = try #require(fixture.theo.id)
        let scheduledFor = fixture.assignment.scheduledFor

        let receipt = try #require(try TodayAbsentMover.moveAbsent(
            from: [fixture.assignment], absent: [mayaID, theoID], to: fixture.tomorrow,
            context: fixture.context, saveCoordinator: fixture.coordinator
        ))
        #expect(try plans(for: fixture.lesson, in: fixture.context) == [fixture.assignment])
        #expect(Set(fixture.assignment.resolvedStudentIDs) == [mayaID, theoID])
        #expect(fixture.assignment.scheduledForDay == fixture.tomorrow)

        try TodayAbsentMover.undo(receipt, context: fixture.context, saveCoordinator: fixture.coordinator)
        #expect(fixture.assignment.scheduledFor == scheduledFor)
        #expect(fixture.assignment.scheduledForDay == fixture.today)
    }

    @Test("Nobody absent, or a lesson already given, moves nothing")
    func nothingToMove() throws {
        let fixture = try makeFixture()
        let mayaID = try #require(fixture.maya.id)
        #expect(try TodayAbsentMover.moveAbsent(
            from: [fixture.assignment], absent: [], to: fixture.tomorrow,
            context: fixture.context, saveCoordinator: fixture.coordinator
        ) == nil)

        fixture.assignment.state = .presented
        #expect(TodayAbsentMover.absentChildren(on: fixture.assignment, absent: [mayaID]).isEmpty)
        #expect(try TodayAbsentMover.moveAbsent(
            from: [fixture.assignment], absent: [mayaID], to: fixture.tomorrow,
            context: fixture.context, saveCoordinator: fixture.coordinator
        ) == nil)
    }
}
