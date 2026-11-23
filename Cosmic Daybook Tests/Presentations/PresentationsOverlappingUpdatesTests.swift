import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// State layer review 2026-11-22, B2: an update of Ready and Brewing that a
/// newer one cancels at its last pause must leave no record of having seen
/// the change, or the newer update finds "nothing changed" and the lists keep
/// their old rows.
@MainActor
@Suite("Presentations overlapping updates (state layer B2)")
struct PresentationsOverlappingUpdatesTests {

    private func start(_ model: PresentationsViewModel, _ context: NSManagedObjectContext) {
        let lessons: [CDLesson] = context.safeFetch(CDFetchRequest(CDLesson.self))
        let students: [CDStudent] = context.safeFetch(CDFetchRequest(CDStudent.self))
        model.update(
            viewContext: context,
            calendar: AppCalendar.shared,
            inboxOrderRaw: "",
            showTestStudents: true,
            testStudentNamesRaw: "",
            lessons: lessons,
            students: students
        )
    }

    private func inboxIDs(_ model: PresentationsViewModel) -> Set<UUID> {
        Set((model.readyLessons + model.blockedLessons).compactMap(\.id))
    }

    @Test("An update cancelled at its last pause leaves the next one to show the change")
    func cancelledUpdateLeavesTheNextToRefresh() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let first = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
        #expect(CoreDataTestHelpers.save(context))

        // Update one runs to its end.
        let model = PresentationsViewModel()
        start(model, context)
        await model.pendingUpdateTask?.value
        #expect(inboxIDs(model) == Set([first.id].compactMap { $0 }))

        // The change: a new lesson with a draft of its own.
        let added = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let second = PresentationFactory.makeDraft(lesson: added, students: [student], context: context)
        #expect(CoreDataTestHelpers.save(context))
        context.processPendingChanges()
        let addedID = try #require(added.id)
        let secondID = try #require(second.id)

        // Update two runs up to its last pause, the one before the lists are
        // set. The lesson lookup is rebuilt just before that pause, so the new
        // lesson showing up in it says the update has got that far.
        start(model, context)
        var turns = 0
        while model.lessonsByIDCache[addedID] == nil, turns < 1_000 {
            await Task.yield()
            turns += 1
        }
        try #require(model.lessonsByIDCache[addedID] != nil, "update two never reached its last pause")
        try #require(!inboxIDs(model).contains(secondID), "update two finished before it could be cancelled")

        // Update three cancels it there, and has the work to do itself.
        start(model, context)
        await model.pendingUpdateTask?.value
        #expect(inboxIDs(model).contains(secondID), "the lists kept their old rows after the overlap")
        #expect(inboxIDs(model).contains(try #require(first.id)))
    }
}
