import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-11-03 review of the restore fixes (bug hunt 2026-11-02, #1): a
// Merge still took the backup's row for every type without a `modifiedAt`,
// so a note edited since the backup went back, and a to-do ticked since came
// back open (the report's own scenario). Notes are judged by their
// `updatedAt` now, to-dos by when they were done (`BackupMergeRule`), and the
// preview shows what a Merge keeps.

@Suite("Restore review fixes (2026-11-03): a Merge keeps note edits and ticks made since the backup", .serialized)
@MainActor
struct BackupMergeReviewFixTests {

    private static func todo(_ title: String, doneAt: Date?, in context: NSManagedObjectContext) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.isCompleted = doneAt != nil
        todo.completedAt = doneAt
        return todo
    }

    private static func todos(in context: NSManagedObjectContext) -> [UUID: CDTodoItem] {
        Dictionary(uniqueKeysWithValues: context.safeFetch(CDFetchRequest(CDTodoItem.self)).compactMap { todo in
            todo.id.map { ($0, todo) }
        })
    }

    @Test("A note edited since the backup keeps its words and its children; an older one takes the backup's")
    func noteEditsSinceTheBackupStay() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada").id)
        let bea = try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: "Bea").id)
        let cy = try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy").id)
        let edited = CoreDataTestHelpers.seedNote(in: context, body: "Ada and Bea built the tower")
        edited.scope = .students([ada, bea])
        edited.syncStudentLinks(in: context)
        edited.updatedAt = Fix1102.at(10)
        let behind = CoreDataTestHelpers.seedNote(in: context, body: "Cy read aloud")
        behind.updatedAt = Fix1102.at(10)
        try context.save()
        let editedID = try #require(edited.id)
        let behindID = try #require(behind.id)

        var backup = Fix1102.payload(of: context)
        // The backup's copy of the second note is newer than this device's
        // (this device is behind).
        let behindRow = try #require(backup.notes.firstIndex { $0.id == behindID })
        backup.notes[behindRow].body = "Cy read aloud to the class"
        backup.notes[behindRow].updatedAt = Fix1102.at(50)

        // Since the backup, here: the note now names Ada and Cy, not Bea.
        edited.body = "Ada and Cy built the tower"
        edited.scope = .students([ada, cy])
        edited.syncStudentLinks(in: context)
        edited.updatedAt = Fix1102.at(50)
        try context.save()

        let preview = Fix1102.analyze(BackupPreviewDigest(payload: backup), against: context, mode: .merge)
        #expect(preview.kept["Note"] == 1, "the note edited since the backup is kept")
        #expect(preview.skips["Note"] == 1, "the note older here takes the backup's version")

        try await Fix1102.restore(backup, into: context, mode: .merge)
        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        let editedAfter = try #require(notes.first { $0.id == editedID })
        #expect(editedAfter.body == "Ada and Cy built the tower")
        #expect(editedAfter.scope == .students([ada, cy]))
        let linked = Set((editedAfter.studentLinks?.allObjects as? [CDNoteStudentLink] ?? [])
            .filter { !$0.isDeleted }.compactMap { UUID(uuidString: $0.studentID) })
        #expect(linked == [ada, cy], "the backup's link to Bea doesn't come back to a note that no longer names her")
        #expect(notes.first { $0.id == behindID }?.body == "Cy read aloud to the class")
    }

    @Test("A to-do done since the backup stays done; the rest of a to-do takes the backup's version")
    func toDosDoneSinceTheBackupStayDone() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let tickedSince = Self.todo("Ticked since", doneAt: nil, in: context)
        let doneAgain = Self.todo("Done again", doneAt: Fix1102.at(20), in: context)
        let doneLaterThere = Self.todo("Done later there", doneAt: Fix1102.at(20), in: context)
        let tickedThere = Self.todo("Ticked there", doneAt: nil, in: context)
        let open = Self.todo("Open", doneAt: nil, in: context)
        let unticked = Self.todo("Unticked", doneAt: nil, in: context)
        try context.save()
        let ids = try [tickedSince, doneAgain, doneLaterThere, tickedThere, open, unticked]
            .map { try #require($0.id) }

        var backup = Fix1102.payload(of: context)
        func edit(_ id: UUID, _ change: (inout TodoItemDTO) -> Void) throws {
            var items = try #require(backup.todoItems)
            let index = try #require(items.firstIndex { $0.id == id })
            change(&items[index])
            backup.todoItems = items
        }
        try edit(ids[1]) { $0.title = "Done again (backup)" }
        try edit(ids[2]) { $0.title = "Done later there (backup)"; $0.completedAt = Fix1102.at(50) }
        try edit(ids[3]) { $0.title = "Ticked there (backup)"; $0.isCompleted = true; $0.completedAt = Fix1102.at(30) }
        try edit(ids[4]) { $0.title = "Open (backup)" }
        try edit(ids[5]) { $0.title = "Unticked (backup)" }

        // Since the backup, here.
        tickedSince.isCompleted = true
        tickedSince.completedAt = Fix1102.at(40)
        doneAgain.title = "Done again (here)"
        doneAgain.completedAt = Fix1102.at(50)
        doneLaterThere.title = "Done later there (here)"
        tickedThere.title = "Ticked there (here)"
        open.title = "Open (here)"
        // Unticked by a path that left the done date: open, so no tick to keep.
        unticked.title = "Unticked (here)"
        unticked.completedAt = Fix1102.at(60)
        try context.save()

        let preview = Fix1102.analyze(BackupPreviewDigest(payload: backup), against: context, mode: .merge)
        #expect(preview.kept["TodoItem"] == 2, "the two done here since the backup's version")
        #expect(preview.skips["TodoItem"] == 4)

        try await Fix1102.restore(backup, into: context, mode: .merge)
        let after = Self.todos(in: context)
        let ticked = try #require(after[ids[0]])
        #expect(ticked.isCompleted && ticked.completedAt == Fix1102.at(40), "a tick since the backup isn't undone")
        let again = try #require(after[ids[1]])
        #expect(again.title == "Done again (here)", "done here after the backup's done: kept whole")
        #expect(again.completedAt == Fix1102.at(50))
        let later = try #require(after[ids[2]])
        #expect(later.title == "Done later there (backup)", "the backup's done is the later one: the backup's")
        #expect(later.completedAt == Fix1102.at(50))
        let tickedInBackup = try #require(after[ids[3]])
        #expect(tickedInBackup.isCompleted, "open here, done in the backup: ticked")
        #expect(tickedInBackup.title == "Ticked there (backup)")
        // A to-do has no change date: its other edits can't be judged, and
        // the Settings line says they go back.
        #expect(after[ids[4]]?.title == "Open (backup)")
        #expect(after[ids[5]]?.title == "Unticked (backup)", "a done date on an open to-do counts for nothing")
    }

    @Test("The Merge preview passes on what it keeps, and an untouched record isn't counted as kept")
    func previewShowsKept() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let bea = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bea")
        // Dates with a fraction, which the archive keeps to the millisecond.
        ada.setValue(Date(timeIntervalSinceNow: -120.4567), forKey: "modifiedAt")
        bea.setValue(Date(timeIntervalSinceNow: -120.4567), forKey: "modifiedAt")
        #expect(CoreDataTestHelpers.save(context))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: context, to: url)

        ada.firstName = "Ada (since)"
        ada.setValue(Date(), forKey: "modifiedAt")
        #expect(CoreDataTestHelpers.save(context))

        let coordinator = BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(), appRouter: AppRouter()
        )
        let preview = try await coordinator.previewImport(
            viewContext: context, from: url, mode: .merge, progress: { _, _ in }
        )
        #expect(preview.entityKept["Student"] == 1, "Ada, changed since the backup")
        #expect(preview.entitySkips["Student"] == 1, "Bea, untouched: her row is the version here")
        #expect(preview.totalKept == 1)
    }

    @Test("The kinds the Merge wording names are the ones with no change date")
    func namedKindsHaveNoChangeDate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let model = try #require(context.persistentStoreCoordinator?.managedObjectModel)
        // The Settings line and the preview say a Merge brings these back to
        // the backup's version. If one gains a change date, reword them.
        for name in ["Lesson", "WorkModel", "LessonPresentation", "StudentMeeting", "TodoItem"] {
            let entity = try #require(model.entitiesByName[name])
            #expect(BackupMergeRule.changeDateAttribute(of: entity) == nil, "\(name)")
        }
        for name in ["Student", "Note", "AttendanceRecord", "Supply", "LessonAssignment"] {
            let entity = try #require(model.entitiesByName[name])
            #expect(BackupMergeRule.changeDateAttribute(of: entity) != nil, "\(name)")
        }
        #expect(BackupMergeRule.changeDateAttribute(of: try #require(model.entitiesByName["Note"])) == "updatedAt")
        let todo = try #require(model.entitiesByName["TodoItem"])
        #expect(BackupMergeRule.completionAttribute(of: todo) == "completedAt")
    }

    @Test("A stored date is later only past the precision the backup kept")
    func laterAtTheBackupsPrecision() {
        let whole = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(!BackupMergeRule.isLater(whole.addingTimeInterval(0.9), than: whole), "a whole-second backup")
        #expect(BackupMergeRule.isLater(whole.addingTimeInterval(1), than: whole))
        let millis = whole.addingTimeInterval(0.122)
        #expect(!BackupMergeRule.isLater(whole.addingTimeInterval(0.1229), than: millis), "a millisecond backup")
        #expect(BackupMergeRule.isLater(whole.addingTimeInterval(0.2), than: millis))
        #expect(!BackupMergeRule.isLater(whole, than: millis), "earlier")
    }
}
