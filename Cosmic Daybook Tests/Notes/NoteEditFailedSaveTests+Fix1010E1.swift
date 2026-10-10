import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review round 2026-10-10. When saving an edit to an existing note failed,
// the new text, scope, links and photo stayed in the view context: Discard
// Changes discarded nothing, and the next unrelated save wrote the edit and
// synced it. A failed save now puts the note back as it was.

@Suite("Failed note edits leave the note as it was (Fix1010E1)")
@MainActor
struct NoteEditFailedSaveTests {

    private struct Seeded {
        let context: NSManagedObjectContext
        let note: CDNote
        let poison: CDNoteStudentLink
        let etty: UUID
        let ora: UUID
    }

    /// A saved note about Etty and Ora, then something in the context that
    /// makes every save fail (a link with no note id, which the model requires).
    private func seed() throws -> Seeded {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Built the cube.")
        note.scope = .students([etty, ora])
        note.tagsArray = ["Math"]
        note.imagePath = "old.jpg"
        note.syncStudentLinks(in: context)
        #expect(CoreDataTestHelpers.save(context))
        let poison = CDNoteStudentLink(context: context)
        poison.setValue(nil, forKey: "noteID")
        return Seeded(context: context, note: note, poison: poison, etty: etty, ora: ora)
    }

    /// The note as the store has it once the failure's cause is gone and the
    /// context saves for some other reason.
    private func savedLater(_ seeded: Seeded) throws -> CDNote {
        seeded.context.delete(seeded.poison)
        #expect(CoreDataTestHelpers.save(seeded.context))
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = seeded.context.persistentStoreCoordinator
        let noteID = try #require(seeded.note.id)
        return try #require(reader.object(CDNote.self, id: noteID))
    }

    private func linkedStudents(of note: CDNote) -> [String] {
        ((note.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? [])
            .filter { !$0.isDeleted }
            .map { $0.studentID.uppercased() }
            .sorted()
    }

    @Test("A failed save in the note editor puts the text, scope, links and photo back")
    func editorRollsBack() throws {
        let seeded = try seed()
        let fields = NoteEditorSave.Fields(
            body: "Built the cube with Tiffy.", tags: ["Math", "Social"], includeInReport: true,
            needsFollowUp: true, imagePath: "new.jpg", scope: .students([seeded.etty, UUID()])
        )
        let outcome = NoteEditorSave.save(
            fields, to: .existing(seeded.note, originalImagePath: "old.jpg"),
            in: seeded.context, saveCoordinator: .preview
        )
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(seeded.note.body == "Built the cube.")
        #expect(seeded.note.imagePath == "old.jpg")
        #expect(seeded.note.changedValues().isEmpty, "nothing of the edit is left waiting to be saved")

        let stored = try savedLater(seeded)
        #expect(stored.body == "Built the cube.")
        #expect(stored.tagsArray == ["Math"])
        #expect(!stored.includeInReport)
        #expect(stored.imagePath == "old.jpg")
        #expect(Set(stored.scope.studentIDs ?? []) == Set([seeded.etty, seeded.ora]))
        #expect(linkedStudents(of: stored) == [seeded.etty, seeded.ora].map(\.uuidString).sorted())
    }

    @Test("A failed save in the note sheet puts the text and flags back")
    func sheetRollsBack() throws {
        let seeded = try seed()
        let edit = NoteEditorSave.SheetEdit(
            body: "Changed.", tags: [], includeInReport: true, isPinned: true, needsFollowUp: true
        )
        let outcome = NoteEditorSave.save(edit, to: seeded.note, in: seeded.context, saveCoordinator: .preview)
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(seeded.note.changedValues().isEmpty)

        let stored = try savedLater(seeded)
        #expect(stored.body == "Built the cube.")
        #expect(stored.tagsArray == ["Math"])
        #expect(!stored.isPinned)
        #expect(!stored.needsFollowUp)
    }

    @Test("The rollback leaves other screens' unsaved changes alone")
    func othersUntouched() throws {
        let seeded = try seed()
        let other = CoreDataTestHelpers.seedNote(in: seeded.context, body: "Another screen's unsaved note.")
        let edit = NoteEditorSave.SheetEdit(
            body: "Changed.", tags: [], includeInReport: false, isPinned: false, needsFollowUp: false
        )
        _ = NoteEditorSave.save(edit, to: seeded.note, in: seeded.context, saveCoordinator: .preview)
        #expect(seeded.context.insertedObjects.contains(other))
        #expect(seeded.context.insertedObjects.contains(seeded.poison))
    }

    @Test("A saved edit still saves")
    func successSaves() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Before.")
        #expect(CoreDataTestHelpers.save(context))
        let edit = NoteEditorSave.SheetEdit(
            body: "After.", tags: ["Art"], includeInReport: false, isPinned: true, needsFollowUp: false
        )
        guard case .saved = NoteEditorSave.save(edit, to: note, in: context, saveCoordinator: .preview) else {
            Issue.record("expected the edit to save")
            return
        }
        #expect(!context.hasChanges)
        #expect(note.body == "After.")
        #expect(note.isPinned)
    }
}
