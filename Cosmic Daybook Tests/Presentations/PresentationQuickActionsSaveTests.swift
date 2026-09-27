import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The quick-actions sheet's Save: a plan it can't make skips only that plan,
/// never the save and the close. Each "no children" or "no id" case here used
/// to return from the whole Save, leaving the edit unsaved and the sheet open.
@Suite("Presentation Quick Actions Save")
@MainActor
struct PresentationQuickActionsSaveTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let catalog: LessonCatalog
        let student: CDStudent
        let currentLesson: CDLesson
        let nextLesson: CDLesson
    }

    private struct Outcome {
        var closes = 0
        var inboxRefreshes = 0
    }

    /// Two lessons in one sequence and one child, all saved.
    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let currentLesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Mathematics", sequence: "Decimal System"
        )
        currentLesson.orderInSequence = 1
        let nextLesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Large Number Cards", area: "Mathematics", sequence: "Decimal System"
        )
        nextLesson.orderInSequence = 2
        try context.save()
        return Fixture(
            context: context,
            catalog: LessonCatalog(context: context),
            student: student,
            currentLesson: currentLesson,
            nextLesson: nextLesson
        )
    }

    /// A saved, unpresented plan of the current lesson for `students`.
    private func makePresentation(in fixture: Fixture, students: [CDStudent]) throws -> CDLessonAssignment {
        let assignment = PresentationFactory.makeDraft(
            lesson: fixture.currentLesson, students: students, context: fixture.context
        )
        try fixture.context.save()
        return assignment
    }

    private func save(
        _ assignment: CDLessonAssignment,
        in fixture: Fixture,
        presentedNow: Bool,
        needsAnotherPresentation: Bool
    ) -> Outcome {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let context = fixture.context
        var outcome = Outcome()
        PresentationQuickActionsSave(
            lessonAssignment: assignment,
            presentedNow: presentedNow,
            needsAnotherPresentation: needsAnotherPresentation,
            catalog: fixture.catalog,
            lessonAssignmentsAll: { context.safeFetch(CDFetchRequest(CDLessonAssignment.self)) },
            studentsAll: [fixture.student],
            viewContext: context,
            saveCoordinator: coordinator,
            refreshPlanningInbox: { outcome.inboxRefreshes += 1 }
        ).run {
            outcome.closes += 1
        }
        return outcome
    }

    private func plans(of lesson: CDLesson, in fixture: Fixture) throws -> [CDLessonAssignment] {
        let lessonID = try #require(lesson.id)
        return fixture.context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
            .filter { $0.resolvedLessonID == lessonID }
    }

    @Test("Given now with no children attached: saved and closed, no next lesson planned")
    func presentedWithNoChildren() throws {
        let fixture = try makeFixture()
        let assignment = try makePresentation(in: fixture, students: [])

        let outcome = save(assignment, in: fixture, presentedNow: true, needsAnotherPresentation: false)

        #expect(outcome.closes == 1)
        #expect(outcome.inboxRefreshes == 0)
        #expect(!fixture.context.hasChanges)
        #expect(assignment.state == .presented)
        #expect(try plans(of: fixture.nextLesson, in: fixture).isEmpty)
    }

    @Test("Given now when the next lesson has no id: saved and closed")
    func presentedWhenNextLessonHasNoID() throws {
        let fixture = try makeFixture()
        fixture.nextLesson.id = nil
        try fixture.context.save()
        let assignment = try makePresentation(in: fixture, students: [fixture.student])

        let outcome = save(assignment, in: fixture, presentedNow: true, needsAnotherPresentation: false)

        #expect(outcome.closes == 1)
        #expect(outcome.inboxRefreshes == 0)
        #expect(!fixture.context.hasChanges)
        #expect(assignment.state == .presented)
        #expect(fixture.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).count == 1)
    }

    @Test("Needs another presentation with no children attached: the flag is saved and the sheet closes")
    func needsAnotherWithNoChildren() throws {
        let fixture = try makeFixture()
        let assignment = try makePresentation(in: fixture, students: [])

        let outcome = save(assignment, in: fixture, presentedNow: false, needsAnotherPresentation: true)

        #expect(outcome.closes == 1)
        #expect(!fixture.context.hasChanges)
        #expect(assignment.needsAnotherPresentation)
        #expect(try plans(of: fixture.currentLesson, in: fixture).count == 1)
    }

    @Test("With a child attached, both plans are made for her, then saved and closed")
    func plansForAttachedChild() throws {
        let fixture = try makeFixture()
        let studentID = try #require(fixture.student.id)
        let assignment = try makePresentation(in: fixture, students: [fixture.student])

        let outcome = save(assignment, in: fixture, presentedNow: true, needsAnotherPresentation: true)

        #expect(outcome.closes == 1)
        #expect(outcome.inboxRefreshes == 1)
        #expect(!fixture.context.hasChanges)
        #expect(assignment.state == .presented)
        let nextPlans = try plans(of: fixture.nextLesson, in: fixture)
        #expect(nextPlans.count == 1)
        #expect(nextPlans.first?.resolvedStudentIDs == [studentID])
        let repeatPlans = try plans(of: fixture.currentLesson, in: fixture).filter { !$0.isPresented }
        #expect(repeatPlans.count == 1)
        #expect(repeatPlans.first?.resolvedStudentIDs == [studentID])
    }
}
