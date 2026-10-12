import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, #2 and #4.
//
// #2: only Add Lesson refused a name its sub-area already had. The lesson
// editor's Save and dragging a lesson to another sub-area made the pair with
// no check, and the launch merge then folded one lesson into the other. Both
// now refuse with Add Lesson's wording and change nothing.
//
// #4: Bulk Add left its inserts in the context when the save failed, so the
// retry found each lesson's own unsaved copy and called every row "already
// filed". A failed save now takes the inserts back.

@Suite("Lesson filing: one name per sub-area, and Bulk Add's retry (bug hunt 10-12)")
@MainActor
struct LessonFilingFix1012LTests {

    private func lessons(in context: NSManagedObjectContext) -> [CDLesson] {
        context.safeFetch(CDFetchRequest(CDLesson.self)).filter { !$0.isDeleted }
    }

    // MARK: - #2 The lesson editor's Save

    @Test("The editor refuses moving a lesson into a sub-area that has one by its new name, and writes nothing")
    func editorRefusesATwin() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        let fractions = try repository.createLesson(name: "Introduction", area: "Math", sequence: "Fractions")
        let decimals = try repository.createLesson(
            name: "Introduction to Decimals", area: "Math", sequence: "Decimals", writeUp: "Tenths first."
        )
        #expect(CoreDataTestHelpers.save(context))

        var draft = LessonEditDraft(lesson: decimals)
        draft.name = " introduction"
        draft.sequence = "Fractions "
        draft.writeUp = "Halves first."

        #expect(throws: LessonRepository.CreationError.duplicateName(
            existingID: fractions.id, name: "introduction", area: "Math", sequence: "Fractions"
        )) {
            try draft.apply(to: decimals)
        }
        #expect(decimals.name == "Introduction to Decimals")
        #expect(decimals.sequence == "Decimals")
        #expect(decimals.writeUp == "Tenths first.")
        #expect(!context.hasChanges)
    }

    @Test("The editor still saves a free name, and an edit that keeps a lesson's own name and sub-area")
    func editorAllowsFreeNamesAndUnrenamedEdits() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        let lesson = try repository.createLesson(name: "Rectangle", area: "Geometry", sequence: "Area")
        // A pair filed before the check existed: the launch merge folds it, and
        // until then an edit that leaves the name alone still saves.
        let twin = CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle", area: "Geometry", sequence: "Area")
        #expect(CoreDataTestHelpers.save(context))

        var writeUpOnly = LessonEditDraft(lesson: twin)
        writeUpOnly.writeUp = "Base times height."
        #expect(try writeUpOnly.apply(to: twin))
        #expect(twin.writeUp == "Base times height.")

        var renamed = LessonEditDraft(lesson: lesson)
        renamed.name = "Square"
        #expect(try renamed.apply(to: lesson))
        #expect(lesson.name == "Square")
    }

    // MARK: - #2 Dragging a lesson to another sub-area

    @Test("Dragging a lesson into a sub-area that has one by its name is refused, and moves nothing")
    func dragRefusesATwin() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        let moving = try repository.createLesson(
            name: "Introduction", area: "Math", sequence: "Decimals", orderInSequence: 3
        )
        let resident = try repository.createLesson(name: "introduction", area: "Math", sequence: "Fractions")
        let halves = try repository.createLesson(
            name: "Halves", area: "Math", sequence: "Fractions", orderInSequence: 1
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(throws: LessonRepository.CreationError.duplicateName(
            existingID: resident.id, name: "Introduction", area: "Math", sequence: "Fractions"
        )) {
            try LessonSequenceOrdering.moveToEnd(moving, ofSequence: "Fractions", after: [resident, halves])
        }
        #expect(moving.sequence == "Decimals")
        #expect(moving.orderInSequence == 3)
        #expect(!context.hasChanges)
    }

    @Test("Dragging a lesson with a free name files it at the end of the new sub-area")
    func dragMovesAFreeName() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        let moving = try repository.createLesson(name: "Thirds", area: "Math", sequence: "Decimals")
        let halves = try repository.createLesson(
            name: "Halves", area: "Math", sequence: "Fractions", orderInSequence: 1
        )
        #expect(CoreDataTestHelpers.save(context))

        try LessonSequenceOrdering.moveToEnd(moving, ofSequence: "Fractions", after: [halves])
        #expect(moving.sequence == "Fractions")
        #expect(moving.orderInSequence == 2)
    }

    // MARK: - #4 Bulk Add after a failed save

    @Test("Bulk Add's retry after a failed save adds the lessons instead of calling them already filed")
    func bulkRetryAfterFailedSaveAddsTheLessons() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        // Another screen's unsaved row that can't be saved makes the save fail.
        let blocker = CDWorkModel(context: context)
        blocker.setValue(nil, forKey: "title")
        let drafts = ["Rectangle", "Square"].map {
            BulkLessonDraft(name: $0, area: "Geometry", sequence: "Area", section: "", writeUp: "")
        }

        let failed = BulkLessonInsertion.insertAndSave(
            drafts, using: repository, source: .album, personalKind: nil, saveCoordinator: SaveCoordinator.preview
        )
        #expect(failed == nil)
        #expect(!context.insertedObjects.contains { $0 is CDLesson })
        #expect(context.insertedObjects.contains(blocker))

        // The other screen's row is fixed; Save again.
        blocker.title = "Report on whales"
        let retry = try #require(BulkLessonInsertion.insertAndSave(
            drafts, using: repository, source: .album, personalKind: nil, saveCoordinator: SaveCoordinator.preview
        ))
        #expect(retry.inserted.count == 2)
        #expect(retry.skipped.isEmpty)
        #expect(!context.hasChanges)
        #expect(lessons(in: context).map(\.name).sorted() == ["Rectangle", "Square"])
    }
}
