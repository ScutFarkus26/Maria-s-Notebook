import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17 #8: with the Notes layer hidden, clicking a day opened
/// its field empty (or with the holiday), and the commit that followed found
/// the hidden note and deleted or overwrote it. The editor now opens a day
/// with what is stored, whatever the grid shows, and a commit that changed
/// nothing writes nothing.
///
/// Since Simplify the app's Phase 7 what is stored is the day's pad, the
/// note Today's Pad edits too; these pin the same rules against it.
@Suite("Calendar note editor (Fix1017 Cal)")
@MainActor
struct CalendarNoteEditorFix1017Cal {

    private let christmas = CellID(year: 2026, month: 12, day: 25)
    private let plainDay = CellID(year: 2026, month: 10, day: 20)

    @discardableResult
    private func pad(_ text: String, on cell: CellID, in context: NSManagedObjectContext) throws -> CDDayPad {
        let pad = CDDayPad(context: context, day: try #require(cell.startOfDay()))
        pad.body = text
        pad.modifiedAt = Date(timeIntervalSince1970: 1_780_000_000)
        return pad
    }

    private func pads(in context: NSManagedObjectContext) -> [CDDayPad] {
        context.safeFetch(CDFetchRequest(CDDayPad.self)).filter { !$0.isDeleted }
    }

    /// What the grid hands the editor: every day's pad text.
    private func lookup(in context: NSManagedObjectContext) -> [CellID: String] {
        CalendarNoteEditor.padTexts(of: pads(in: context))
    }

    @Test("#8 A day's pad opens with its text, and an unchanged commit leaves it untouched")
    func storedNoteSurvivesUnchangedCommit() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = try pad("Conferences", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let stamp = stored.modifiedAt

        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        #expect(editor.draft == "Conferences")
        editor.commitIfOpen(plainDay, in: context)

        #expect(editor.editingCell == nil)
        #expect(!stored.isDeleted)
        #expect(pads(in: context).count == 1)
        #expect(stored.body == "Conferences")
        #expect(stored.modifiedAt == stamp)
        #expect(!context.hasChanges)
    }

    @Test("#8 A pad on a holiday opens with its text, not the holiday's name")
    func holidayNoteOpensWithNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = try pad("Winter concert", on: christmas, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let editor = CalendarNoteEditor()
        editor.beginEditing(christmas, padTexts: lookup(in: context), in: context)
        #expect(editor.draft == "Winter concert")
        // Opening another day commits this one unchanged.
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        #expect(!stored.isDeleted)
        #expect(stored.body == "Winter concert")
    }

    @Test("#8 A holiday with nothing written opens with its name, and an unchanged commit stores nothing")
    func holidayWithoutNoteStoresNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let editor = CalendarNoteEditor()
        editor.beginEditing(christmas, padTexts: [:], in: context)
        #expect(editor.draft == "Christmas Day")
        editor.commitIfOpen(christmas, in: context)
        #expect(pads(in: context).isEmpty)
    }

    @Test("#8 Typing writes the pad, and emptying the field, or typing the holiday back, empties it")
    func editsStillWrite() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = try pad("Conferences", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let editor = CalendarNoteEditor()

        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        editor.draft = "Conferences, 3:30"
        editor.commitIfOpen(plainDay, in: context)
        #expect(stored.body == "Conferences, 3:30")

        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        editor.draft = "  "
        editor.commitIfOpen(plainDay, in: context)
        #expect(stored.body == "")
        #expect(lookup(in: context)[plainDay] == nil)

        editor.beginEditing(christmas, padTexts: lookup(in: context), in: context)
        editor.draft = "No school"
        editor.commitOpenCell(in: context)
        let christmasDay = try #require(christmas.startOfDay())
        let christmasPad = try #require(TodayDataFetcher.fetchDayPad(day: christmasDay, context: context))
        #expect(christmasPad.body == "No school")

        editor.beginEditing(christmas, padTexts: lookup(in: context), in: context)
        editor.draft = "Christmas Day"
        editor.commitOpenCell(in: context)
        #expect(christmasPad.body == "")
        #expect(!context.hasChanges)
    }

    @Test("The pad written on Today shows whole, and a field holding several lines wraps")
    func multiLinePadOpensWhole() throws {
        let context = try CoreDataTestHelpers.makeContext()
        try pad("Call Maya's dad\n\nOrder golden beads", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(CalendarDayText.padSummary("Call Maya's dad\n\nOrder golden beads")
            == "Call Maya's dad \u{00B7} Order golden beads")
        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        #expect(editor.draft == "Call Maya's dad\n\nOrder golden beads")
        #expect(editor.editsMultipleLines)

        editor.beginEditing(christmas, padTexts: lookup(in: context), in: context)
        #expect(editor.editsMultipleLines == false)
    }

    @Test("A change made to the pad while the field is open is kept, with what she typed added after it")
    func changeMadeMeanwhileIsKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = try pad("Call Maya's dad", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        // Meanwhile, on Today (or another device, synced in):
        stored.setBody("Call Maya's dad\n\nOrder golden beads")
        #expect(CoreDataTestHelpers.save(context))
        editor.draft = "Call Maya's dad\nField trip forms"
        editor.commitIfOpen(plainDay, in: context)

        let body = try #require(stored.body)
        #expect(body.contains("Order golden beads"))
        #expect(body.contains("Field trip forms"))
        #expect(pads(in: context).count == 1)
    }

    @Test("A pad that opened ending in a line break, changed meanwhile, gets only what she added, not itself again")
    func trailingLineBreakDoesNotRepeatThePad() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = try pad("Call Maya's dad\n", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        #expect(editor.draft == "Call Maya's dad\n")
        // Meanwhile, on Today (or another device, synced in):
        stored.setBody("Call Maya's dad\n\nOrder golden beads")
        #expect(CoreDataTestHelpers.save(context))
        // She goes on from the end of her line.
        editor.draft = "Call Maya's dad at 3"
        editor.commitIfOpen(plainDay, in: context)

        let body = try #require(stored.body)
        #expect(body.components(separatedBy: "Call Maya's dad").count - 1 == 1, "\(body)")
        #expect(body == "Call Maya's dad\n\nOrder golden beads\n\nat 3")
    }

    @Test("A pad changed meanwhile only by its spacing counts as unchanged, and takes her text as typed")
    func spacingOnlyChangeIsNotAChange() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = try pad("Picture day\n", on: plainDay, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        // Another device saved it without the line break.
        stored.setBody("Picture day")
        #expect(CoreDataTestHelpers.save(context))
        editor.draft = "Picture day, 9:00"
        editor.commitIfOpen(plainDay, in: context)

        #expect(stored.body == "Picture day, 9:00")
    }

    @Test("Two devices' pads for one day show as one text, and a commit joins them into one pad")
    func twoDevicesPadsShowJoined() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = try pad("Picture day", on: plainDay, in: context)
        first.createdAt = Date(timeIntervalSince1970: 1_780_000_000)
        let second = try pad("Bring forms", on: plainDay, in: context)
        second.createdAt = Date(timeIntervalSince1970: 1_780_000_060)
        #expect(CoreDataTestHelpers.save(context))

        let editor = CalendarNoteEditor()
        editor.beginEditing(plainDay, padTexts: lookup(in: context), in: context)
        #expect(editor.draft == "Picture day\n\nBring forms")
        editor.draft = "Picture day\n\nBring forms\n\nWear uniforms"
        editor.commitIfOpen(plainDay, in: context)

        let remaining = pads(in: context)
        #expect(remaining.count == 1)
        #expect(remaining.first?.body == "Picture day\n\nBring forms\n\nWear uniforms")
    }
}
