import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// State layer review 2026-11-22, "also found": the presentation sheet's notes
/// autosave forgot the notes were unsaved even when its save had failed, so
/// closing the sheet didn't try again.
@MainActor
@Suite("Presentation notes autosave after a failed save (state layer A3)")
struct PresentationNotesAutosaveStateTests {

    /// A row the save can't accept, so every save fails until it is deleted.
    private func poison(_ context: NSManagedObjectContext) -> NSManagedObject {
        let poison = CDNoteStudentLink(context: context)
        poison.setValue(nil, forKey: "noteID")
        return poison
    }

    private func makeViewModel(in context: NSManagedObjectContext) throws -> PresentationDetailViewModel {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Long Chains")
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora")
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
        #expect(CoreDataTestHelpers.save(context))
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: context, saveCoordinator: coordinator
        )
    }

    @Test("A failed autosave keeps the notes unsaved, and closing the sheet saves them")
    func failedAutosaveIsTriedAgainOnClose() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let viewModel = try makeViewModel(in: context)

        // The autosave after typing fails.
        let blocker = poison(context)
        viewModel.notes = "Counted the hundred chain twice"
        await viewModel.notesAutosaveTask?.value
        #expect(context.hasChanges, "the save was meant to fail")
        #expect(viewModel.notesDirty, "a failed autosave still has notes to save")

        // Closing the sheet while it still can't save.
        viewModel.flushNotesAutosaveIfNeeded()
        #expect(context.hasChanges)
        #expect(viewModel.notesDirty, "a failed save on close still has notes to save")

        // Closing it once the save can go through.
        context.delete(blocker)
        viewModel.flushNotesAutosaveIfNeeded()
        #expect(!context.hasChanges)
        #expect(!viewModel.notesDirty)
        #expect(viewModel.lessonAssignment.notes == "Counted the hundred chain twice")
    }
}

/// State layer review 2026-11-22, "also found": the sheet's "Before you start"
/// list refreshed through a debounced publisher its view rebuilt on every
/// draw, which could drop a refresh. The 300 ms wait is on the model now.
@MainActor
@Suite("Presentation sheet refresh wait (state layer A2)")
struct PresentationShowFirstRefreshTests {

    private func makeViewModel() throws -> PresentationDetailViewModel {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Long Chains")
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora")
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
        #expect(CoreDataTestHelpers.save(context))
        return PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: context, saveCoordinator: SaveCoordinator()
        )
    }

    @Test("Two refresh requests inside the wait give one refresh")
    func requestsInsideTheWaitRefreshOnce() async throws {
        let viewModel = try makeViewModel()
        var refreshes: [String] = []

        viewModel.requestWorkToShowFirstRefresh { refreshes.append("first") }
        let first = try #require(viewModel.showFirstRefreshTask)
        viewModel.requestWorkToShowFirstRefresh { refreshes.append("second") }
        let second = try #require(viewModel.showFirstRefreshTask)
        #expect(refreshes.isEmpty, "the refresh waits, it doesn't run at once")

        await first.value
        await second.value
        #expect(refreshes == ["second"])
    }

    @Test("A refresh still waiting when the list leaves the screen doesn't run")
    func cancelledRequestDoesNotRefresh() async throws {
        let viewModel = try makeViewModel()
        var refreshes = 0

        viewModel.requestWorkToShowFirstRefresh { refreshes += 1 }
        let pending = try #require(viewModel.showFirstRefreshTask)
        viewModel.cancelWorkToShowFirstRefresh()

        await pending.value
        #expect(refreshes == 0)
        #expect(viewModel.showFirstRefreshTask == nil)
    }
}
