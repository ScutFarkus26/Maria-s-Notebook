import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #1 and #2. Quick Note made the note and said "Note
// saved" without saving it (the view context doesn't autosave), never posted
// `.noteDidSave`, and never made the student links a multi-child note is
// found by. A chip she took off came back on the next keystroke.

@Suite("Quick Note saving (Fix1010E1)")
@MainActor
struct QuickNoteSaveTests {

    /// A context whose every save fails: it holds a student link with no note
    /// id, a value the model requires, so Core Data refuses the save with a
    /// validation error, as it does a real failed save.
    static func unsavableContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeContext()
        let poison = CDNoteStudentLink(context: context)
        poison.setValue(nil, forKey: "noteID")
        return context
    }

    /// Whether a note is waiting in `context` to be saved.
    static func hasUnsavedNote(in context: NSManagedObjectContext) -> Bool {
        context.processPendingChanges()
        return context.insertedObjects.contains { $0 is CDNote }
    }

    /// The note ids `.noteDidSave` announced while it was open (posted on the main thread).
    @MainActor
    final class SavedNotes {
        var ids: [UUID] = []
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: .noteDidSave, object: nil, queue: nil
            ) { [weak self] note in
                let id = note.object as? UUID
                MainActor.assumeIsolated {
                    if let id { self?.ids.append(id) }
                }
            }
        }

        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }

    @Test("Save writes the note, its links and its date, and tells the note lists")
    func saveSaves() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let etty = UUID()
        let ora = UUID()
        let viewModel = QuickNoteViewModel(
            initialStudentIDs: [etty, ora], initialBodyText: "Etty and Ora built the cube."
        )
        let backdated = try CoreDataTestHelpers.day("2026-10-06")
        viewModel.noteDate = backdated

        let announced = SavedNotes()
        defer { announced.stop() }
        #expect(viewModel.saveNote(viewContext: context, saveCoordinator: .preview))

        #expect(!context.hasChanges, "the note is saved, not left in memory")
        #expect(viewModel.didSave)
        #expect(!viewModel.hasUnsavedContent)

        // Read back through another context: it's in the store.
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let notes = reader.safeFetch(CDFetchRequest(CDNote.self))
        let note = try #require(notes.first)
        #expect(notes.count == 1)
        #expect(note.body == "Etty and Ora built the cube.")
        #expect(note.createdAt == backdated)
        #expect(Set(note.scope.studentIDs ?? []) == Set([etty, ora]))
        let linked = ((note.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? []).map(\.studentID).sorted()
        #expect(linked == [etty, ora].map(\.uuidString).sorted())
        let noteID = try #require(note.id)
        #expect(announced.ids.contains(noteID))

        // Save again does nothing: one note.
        #expect(!viewModel.saveNote(viewContext: context, saveCoordinator: .preview))
        #expect(reader.safeFetch(CDFetchRequest(CDNote.self)).count == 1)
    }

    @Test("A failed save keeps her text, says so, and leaves no half-made note")
    func failedSaveKeepsText() throws {
        let context = try Self.unsavableContext()
        let viewModel = QuickNoteViewModel(initialStudentIDs: [UUID(), UUID()], initialBodyText: "Read aloud.")

        #expect(!viewModel.saveNote(viewContext: context, saveCoordinator: .preview))
        #expect(viewModel.saveErrorMessage != nil)
        #expect(!viewModel.didSave)
        #expect(viewModel.bodyText == "Read aloud.")
        #expect(viewModel.hasUnsavedContent)
        #expect(!Self.hasUnsavedNote(in: context), "trying again makes one note, not two")
    }

    @Test("A child she took off isn't added back by the name finder")
    func removedChipStaysRemoved() {
        let leo = UUID()
        let maya = UUID()
        let viewModel = QuickNoteViewModel(initialStudentIDs: [leo, maya])
        viewModel.removeStudent(leo)
        #expect(viewModel.selectedStudentIDs == [maya])

        let found = StudentMatchResult(exact: [leo], fuzzy: [leo], autoSelect: [leo])
        let matches = viewModel.newMatches(from: found)
        #expect(matches.add.isEmpty)
        #expect(matches.suggest.isEmpty)

        // Putting her back (a suggestion, the picker) forgets that she was taken off.
        viewModel.setSelectedStudents([leo, maya])
        viewModel.removeStudent(maya)
        viewModel.removeStudent(leo)
        viewModel.addStudent(leo)
        #expect(viewModel.selectedStudentIDs == [leo])
        let again = viewModel.newMatches(from: StudentMatchResult(exact: [maya], fuzzy: [], autoSelect: []))
        #expect(again.add.isEmpty, "Maya was taken off too")
    }

    @Test("New matches add exact and unique finds, and suggest the rest once")
    func newMatchesSplit() {
        let leo = UUID()
        let sarahK = UUID()
        let sarahM = UUID()
        let chosen = UUID()
        let viewModel = QuickNoteViewModel(initialStudentIDs: [chosen])
        let result = StudentMatchResult(exact: [leo, chosen], fuzzy: [sarahK, sarahM, leo], autoSelect: [])
        let matches = viewModel.newMatches(from: result)
        #expect(matches.add == [leo])
        #expect(matches.suggest == [sarahK, sarahM])
    }
}
