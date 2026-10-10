import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #2, #12 and #16. The note editor never synced a
// note's student links (re-scoping left the old ones), closed as if saved
// when the save failed, and deleted the note's old photo before saving.
// Suggest Tags › Apply replaced the chosen children and picked the first of
// two Sarahs.

@Suite("Note editor saving (Fix1010E1)")
@MainActor
struct NoteEditorSaveTests {

    private func fields(
        _ body: String, scope: NoteScope, imagePath: String? = nil
    ) -> NoteEditorSave.Fields {
        NoteEditorSave.Fields(
            body: body, tags: [], includeInReport: false, needsFollowUp: false,
            imagePath: imagePath, scope: scope
        )
    }

    private func linkedStudents(of note: CDNote) -> [String] {
        ((note.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? [])
            .filter { !$0.isDeleted }
            .map { $0.studentID.uppercased() }
            .sorted()
    }

    /// Writes a throwaway photo into the local note-photo folder.
    private func makePhoto() throws -> (name: String, url: URL) {
        let name = "Fix1010E1-\(UUID().uuidString).jpg"
        let url = try PhotoStorageService.localPhotosDirectory().appendingPathComponent(name)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        return (name, url)
    }

    @Test("A new multi-child note saves with a link for each child")
    func newNoteLinks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame")
        #expect(CoreDataTestHelpers.save(context))

        let outcome = NoteEditorSave.save(
            fields("Both carried to the thousands.", scope: .students([etty, ora])),
            to: .new(attach: { $0.lesson = lesson }),
            in: context, saveCoordinator: .preview
        )
        guard case .saved(let note) = outcome else {
            Issue.record("expected a saved note, got \(outcome)")
            return
        }
        #expect(!context.hasChanges)
        #expect(note.lessonID == lesson.id?.uuidString)
        #expect(linkedStudents(of: note) == [etty, ora].map(\.uuidString).sorted())
    }

    @Test("Re-scoping a note moves its links with it")
    func rescopeMovesLinks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let tiffy = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Worked together.")
        note.scope = .students([etty, ora])
        note.syncStudentLinks(in: context)
        #expect(CoreDataTestHelpers.save(context))

        let outcome = NoteEditorSave.save(
            fields("Worked together.", scope: .students([etty, tiffy])),
            to: .existing(note, originalImagePath: nil),
            in: context, saveCoordinator: .preview
        )
        guard case .saved = outcome else {
            Issue.record("expected a saved note, got \(outcome)")
            return
        }
        #expect(linkedStudents(of: note) == [etty, tiffy].map(\.uuidString).sorted())

        // Down to one child: no links left behind.
        _ = NoteEditorSave.save(
            fields("Worked together.", scope: .student(etty)),
            to: .existing(note, originalImagePath: nil),
            in: context, saveCoordinator: .preview
        )
        #expect(linkedStudents(of: note).isEmpty)
    }

    @Test("A failed save says so and takes a new note back out")
    func failedSaveNewNote() throws {
        let context = try QuickNoteSaveTests.unsavableContext()
        var attached = false
        let outcome = NoteEditorSave.save(
            fields("Painted.", scope: .students([UUID(), UUID()])),
            to: .new(attach: { _ in attached = true }),
            in: context, saveCoordinator: .preview
        )
        guard case .failed(let message) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(attached)
        #expect(!QuickNoteSaveTests.hasUnsavedNote(in: context))
    }

    @Test("The old photo goes only once the note is saved without it")
    func oldPhotoAfterSave() throws {
        let old = try makePhoto()
        let new = try makePhoto()
        defer {
            try? FileManager.default.removeItem(at: old.url)
            try? FileManager.default.removeItem(at: new.url)
        }

        // A failed save keeps the note's photo on disk.
        let unsavable = try QuickNoteSaveTests.unsavableContext()
        let pending = CoreDataTestHelpers.seedNote(in: unsavable, body: "Map work.")
        pending.imagePath = old.name
        let failed = NoteEditorSave.save(
            fields("Map work.", scope: .all, imagePath: new.name),
            to: .existing(pending, originalImagePath: old.name),
            in: unsavable, saveCoordinator: .preview
        )
        guard case .failed = failed else {
            Issue.record("expected a failure, got \(failed)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: old.url.path), "deleted first, it was lost on a failed save")

        // A saved change of photo deletes the old one.
        let context = try CoreDataTestHelpers.makeContext()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Map work.")
        note.imagePath = old.name
        #expect(CoreDataTestHelpers.save(context))
        let saved = NoteEditorSave.save(
            fields("Map work.", scope: .all, imagePath: new.name),
            to: .existing(note, originalImagePath: old.name),
            in: context, saveCoordinator: .preview
        )
        guard case .saved = saved else {
            Issue.record("expected a saved note, got \(saved)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: old.url.path))
        #expect(FileManager.default.fileExists(atPath: new.url.path))
    }

    @Test("Closing without saving deletes only a photo the editor attached")
    func discardDeletesOnlyNewPhoto() throws {
        let original = try makePhoto()
        let added = try makePhoto()
        defer {
            try? FileManager.default.removeItem(at: original.url)
            try? FileManager.default.removeItem(at: added.url)
        }
        NoteEditorSave.deleteUnsavedPhoto(original.name, original: original.name)
        #expect(FileManager.default.fileExists(atPath: original.url.path))
        NoteEditorSave.deleteUnsavedPhoto(added.name, original: original.name)
        #expect(!FileManager.default.fileExists(atPath: added.url.path))
    }

    @Test("Suggest Tags counts a name only when one child answers to it")
    func suggestedNamesAreUnambiguous() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let sarahK = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Katz")
        let sarahM = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Mizrahi")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Adler")
        let students = [sarahK, sarahM, leo]

        func match(_ names: [String]) -> [UUID] {
            SuggestedStudentMatcher.studentIDs(for: names, among: students)
        }
        let sarahMID = try #require(sarahM.id)
        let sarahKID = try #require(sarahK.id)
        let leoID = try #require(leo.id)
        #expect(match(["Sarah"]).isEmpty)
        #expect(match(["Sarah Mizrahi"]) == [sarahMID])
        #expect(match(["Sarah K"]) == [sarahKID])
        #expect(match(["leo", "Leo Adler"]) == [leoID])
        #expect(match(["Mia", ""]).isEmpty)
    }
}
