import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-03 #2 and #13, the new flow: Unmark Presented and Remove Plan ask
/// before deleting a record that was given or carries notes, and a failed save raises
/// "Couldn't Save".
@Suite("Checklist removals ask first (11-03 C)")
@MainActor
struct ChecklistRemovalFix1103CTests {

    typealias Fixture = ChecklistFix1103CFixture

    /// Maya alone on a presentation given Oct 20, with a note on it.
    private func givenWithNote(_ fixture: Fixture) throws -> (given: CDLessonAssignment, note: CDNote) {
        let given = try fixture.give([fixture.maya], on: "2026-10-20")
        let note = CDNote(context: fixture.context)
        note.body = "Counted to a hundred on her own."
        note.scope = .student(try #require(fixture.maya.id))
        note.lessonAssignment = given
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)
        return (given, note)
    }

    @Test("#2: the menu's Unmark Presented names what goes, and Unmark keeps her note")
    func unmarkAsksThenKeepsNote() throws {
        let fixture = try Fixture.make()
        let (given, note) = try givenWithNote(fixture)
        let cell = try fixture.cell(fixture.maya, fixture.first)

        fixture.viewModel.perform(.togglePresented, on: cell, context: fixture.context)

        let request = try #require(fixture.viewModel.pendingRemoval)
        #expect(request.summary.wasGiven)
        #expect(request.summary.noteCount == 1)
        #expect(request.title == "Unmark Presented?")
        #expect(request.message.contains("Decimal 0"))
        #expect(request.message.contains("Its note stays"))

        fixture.viewModel.confirmRemoval(request, context: fixture.context)

        #expect(fixture.viewModel.pendingRemoval == nil)
        #expect(given.isDeleted || given.managedObjectContext == nil)
        #expect(!note.isDeleted && note.managedObjectContext != nil)
        #expect(note.lessonID == fixture.firstID)
        #expect(!fixture.context.hasChanges)
        #expect(fixture.status(fixture.maya, fixture.first) == .ready)
    }

    @Test("#2: Cancel leaves the presentation as it was")
    func cancelKeepsPresentation() throws {
        let fixture = try Fixture.make()
        let (given, _) = try givenWithNote(fixture)

        fixture.viewModel.perform(
            .togglePresented, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )
        fixture.viewModel.cancelRemoval()

        #expect(fixture.viewModel.pendingRemoval == nil)
        #expect(!given.isDeleted && given.managedObjectContext != nil)
        #expect(given.studentIDs == [fixture.maya.cloudKitKey])
        #expect(fixture.status(fixture.maya, fixture.first) == .presented)
    }

    @Test("#2: taking her off a group asks nothing; the others stay on it")
    func groupUnmarkAsksNothing() throws {
        let fixture = try Fixture.make()
        let given = try fixture.give([fixture.maya, fixture.eli], on: "2026-10-20")
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(
            .togglePresented, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        #expect(fixture.viewModel.pendingRemoval == nil)
        #expect(given.studentIDs == [fixture.eli.cloudKitKey])
        #expect(fixture.status(fixture.maya, fixture.first) == .ready)
    }

    @Test("#2: a plain plan with nothing on it goes without asking")
    func plainPlanRemovesWithoutAsking() throws {
        let fixture = try Fixture.make()
        let plan = PresentationFactory.makeDraft(
            lesson: fixture.first, students: [fixture.maya], context: fixture.context
        )
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(
            .toggleScheduled, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        #expect(fixture.viewModel.pendingRemoval == nil)
        #expect(plan.isDeleted || plan.managedObjectContext == nil)
    }

    @Test("#2: a plan with a note asks before Remove Plan")
    func planWithNoteAsks() throws {
        let fixture = try Fixture.make()
        let plan = PresentationFactory.makeDraft(
            lesson: fixture.first, students: [fixture.maya], context: fixture.context
        )
        let note = CDNote(context: fixture.context)
        note.body = "Use the golden beads."
        note.scope = .student(try #require(fixture.maya.id))
        note.lessonAssignment = plan
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(
            .toggleScheduled, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        let request = try #require(fixture.viewModel.pendingRemoval)
        #expect(!request.summary.wasGiven)
        #expect(request.title == "Remove This Plan?")
        #expect(!plan.isDeleted && plan.managedObjectContext != nil)
    }

    // MARK: - #13 Couldn't Save

    @Test("#13: a failed save raises Couldn't Save")
    func failedSaveRaisesAlert() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = ChecklistRulesFix1103CTests.SaveFailingContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = stack.viewContext.persistentStoreCoordinator
        let fixture = try Fixture.make(context: context)
        context.failsSaves = true

        fixture.viewModel.perform(
            .markPresented, on: try fixture.cell(fixture.maya, fixture.first), context: context
        )

        #expect(fixture.viewModel.saveCoordinator.isShowingSaveError)
        #expect(fixture.viewModel.saveCoordinator.lastSaveErrorMessage != nil)
        withExtendedLifetime(stack) {}
    }
}
