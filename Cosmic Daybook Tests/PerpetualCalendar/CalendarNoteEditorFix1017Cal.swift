import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17 #8: with the Notes layer hidden, clicking a day opened
/// its field empty (or with the holiday), and the commit that followed found
/// the hidden note and deleted or overwrote it. The editor now opens a day
/// with what is stored, whatever the grid shows, and a commit that changed
/// nothing writes nothing.
@Suite("Calendar note editor (Fix1017 Cal)")
@MainActor
struct CalendarNoteEditorFix1017Cal {

    private let christmas = CellID(year: 2026, month: 12, day: 25)
    private let plainDay = CellID(year: 2026, month: 10, day: 20)

    private func note(_ text: String, on cell: CellID, in context: NSManagedObjectContext) -> CDCalendarNote {
        let note = CDCalendarNote(context: context)
        note.year = Int64(cell.year)
        note.month = Int64(cell.month)
        note.day = Int64(cell.day)
        note.text = text
        note.modifiedAt = Date(timeIntervalSince1970: 1_780_000_000)
        return note
    }

    private func notes(in context: NSManagedObjectContext) -> [CDCalendarNote] {
        context.safeFetch(CDFetchRequest(CDCalendarNote.self))
    }

    @Test("#8 A stored note opens with its text, and an unchanged commit keeps it untouched")
    func storedNoteSurvivesUnchangedCommit() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = note("Conferences", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let lookup = [plainDay: stored]
        let stamp = stored.modifiedAt

        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, notes: lookup, in: context)
        #expect(editor.draft == "Conferences")
        editor.commitIfOpen(plainDay, notes: lookup, in: context)

        #expect(editor.editingCell == nil)
        #expect(!stored.isDeleted)
        #expect(notes(in: context).count == 1)
        #expect(stored.text == "Conferences")
        #expect(stored.modifiedAt == stamp)
    }

    @Test("#8 A note on a holiday opens with the note, not the holiday's name")
    func holidayNoteOpensWithNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = note("Winter concert", on: christmas, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let lookup = [christmas: stored]

        let editor = CalendarNoteEditor()
        editor.beginEditing(christmas, notes: lookup, in: context)
        #expect(editor.draft == "Winter concert")
        // Opening another day commits this one unchanged.
        editor.beginEditing(plainDay, notes: lookup, in: context)
        #expect(!stored.isDeleted)
        #expect(stored.text == "Winter concert")
    }

    @Test("#8 A holiday with no note opens with its name, and an unchanged commit stores nothing")
    func holidayWithoutNoteStoresNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let editor = CalendarNoteEditor()
        editor.beginEditing(christmas, notes: [:], in: context)
        #expect(editor.draft == "Christmas Day")
        editor.commitIfOpen(christmas, notes: [:], in: context)
        #expect(notes(in: context).isEmpty)
    }

    @Test("#8 Typing still writes, and emptying a note still deletes it")
    func editsStillWrite() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = note("Conferences", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let lookup = [plainDay: stored]
        let editor = CalendarNoteEditor()

        editor.beginEditing(plainDay, notes: lookup, in: context)
        editor.draft = "Conferences, 3:30"
        editor.commitIfOpen(plainDay, notes: lookup, in: context)
        #expect(stored.text == "Conferences, 3:30")

        editor.beginEditing(plainDay, notes: lookup, in: context)
        editor.draft = "  "
        editor.commitIfOpen(plainDay, notes: lookup, in: context)
        #expect(notes(in: context).isEmpty)

        editor.beginEditing(christmas, notes: [:], in: context)
        editor.draft = "No school"
        editor.commitOpenCell(notes: [:], in: context)
        #expect(notes(in: context).map(\.text) == ["No school"])
    }
}
