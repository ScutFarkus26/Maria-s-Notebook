import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 7: the Calendar's notes (`CDCalendarNote`) are
/// copied into their days' pads (`CDDayPad`), the one day note. The copy runs
/// every launch on the guide's notebook, so it has to add each note once and
/// only once, keep everything already on a pad, and lose nothing. What it has
/// done is a mark on the note itself (`CalendarNotePadCopy.copiedMark` as its
/// `modifiedAt`), which syncs, backs up and restores with the pads.
@Suite("Calendar notes copied into day pads")
@MainActor
struct CalendarNotePadCopyTests {

    let fieldTrip = CellID(year: 2026, month: 10, day: 20)
    let pictureDay = CellID(year: 2026, month: 10, day: 21)

    // MARK: - Fixtures (shared with CalendarNotePadCopyTests+Launch.swift)

    @discardableResult
    func note(
        _ text: String, on cell: CellID, id: UUID = UUID(), made: TimeInterval = 0,
        in context: NSManagedObjectContext
    ) -> CDCalendarNote {
        let note = CDCalendarNote(context: context)
        note.id = id
        note.year = Int64(cell.year)
        note.month = Int64(cell.month)
        note.day = Int64(cell.day)
        note.text = text
        note.createdAt = Date(timeIntervalSince1970: 1_780_000_000 + made)
        note.modifiedAt = note.createdAt
        return note
    }

    @discardableResult
    func pad(
        _ body: String, on cell: CellID, id: UUID = UUID(), made: TimeInterval = 0,
        in context: NSManagedObjectContext
    ) throws -> CDDayPad {
        let pad = CDDayPad(context: context, day: try #require(cell.startOfDay()))
        pad.id = id
        pad.body = body
        pad.createdAt = Date(timeIntervalSince1970: 1_770_000_000 + made)
        return pad
    }

    func pads(on cell: CellID, in context: NSManagedObjectContext) throws -> [CDDayPad] {
        let request = CDFetchRequest(CDDayPad.self)
        request.predicate = NSPredicate(format: "day == %@", try #require(cell.startOfDay()) as NSDate)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    func body(on cell: CellID, in context: NSManagedObjectContext) throws -> String? {
        let found = try pads(on: cell, in: context)
        #expect(found.count <= 1, "one pad per day")
        return found.first?.body
    }

    func copy(_ context: NSManagedObjectContext) -> CalendarNotePadCopy.Outcome {
        let outcome = CalendarNotePadCopy.run(in: context)
        #expect(CoreDataTestHelpers.save(context))
        return outcome
    }

    /// `note` as copied: what a Mac that copied it saved, and what reaches
    /// every other device (and every backup) with it.
    @discardableResult
    func marked(_ note: CDCalendarNote) -> CDCalendarNote {
        note.modifiedAt = CalendarNotePadCopy.copiedMark
        return note
    }

    func occurrences(of text: String, in body: String?) -> Int {
        (body ?? "").components(separatedBy: text).count - 1
    }

    // MARK: - Copy and append

    @Test("A note on a day with no pad becomes that day's pad; the note keeps its text and is marked copied")
    func copiesIntoANewPad() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let original = note("  Field trip to the zoo \n", on: fieldTrip, in: context)
        let stamp = try #require(original.modifiedAt)
        #expect(stamp != CalendarNotePadCopy.copiedMark)
        #expect(!CalendarNotePadCopy.isCopied(original))
        #expect(CoreDataTestHelpers.save(context))

        let outcome = copy(context)

        #expect(outcome == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(try body(on: fieldTrip, in: context) == "Field trip to the zoo")
        #expect(!original.isDeleted)
        #expect(original.text == "  Field trip to the zoo \n")
        #expect(original.createdAt == Date(timeIntervalSince1970: 1_780_000_000))
        // Marked on its row, in the same save as the pad.
        #expect(original.modifiedAt == CalendarNotePadCopy.copiedMark)
        #expect(CalendarNotePadCopy.isCopied(original))
        #expect(!context.hasChanges)
    }

    @Test("A note goes after what the day's pad already says, after a blank line")
    func appendsToAnExistingPad() throws {
        let context = try CoreDataTestHelpers.makeContext()
        try pad("Call Maya's dad about the trip.", on: fieldTrip, in: context)
        note("Field trip to the zoo", on: fieldTrip, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(try body(on: fieldTrip, in: context) == "Call Maya's dad about the trip.\n\nField trip to the zoo")
    }

    @Test("Two notes on one day go in the order they were made")
    func twoNotesOnOneDayInOrder() throws {
        let context = try CoreDataTestHelpers.makeContext()
        note("Bring permission forms", on: fieldTrip, made: 60, in: context)
        note("Field trip to the zoo", on: fieldTrip, made: 0, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 2))
        #expect(try body(on: fieldTrip, in: context) == "Field trip to the zoo\n\nBring permission forms")
    }

    @Test("A pad that already has it, spacing and case aside, gets only the mark; a word that only starts so is added")
    func alreadyThereIsNotAdded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let tripPad = try pad("Morning:\nfield  trip TO the zoo, 9:00", on: fieldTrip, in: context)
        try pad("PEACE assembly", on: pictureDay, in: context)
        let trip = note("Field trip to the zoo", on: fieldTrip, in: context)
        let gym = note("PE", on: pictureDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let padStamp = tripPad.modifiedAt

        let outcome = CalendarNotePadCopy.run(in: context)
        #expect(outcome == CalendarNotePadCopy.Outcome(copied: 1, alreadyThere: 1))
        // The pad that had it is untouched: only the note changed.
        #expect(!tripPad.hasChanges)
        #expect(trip.hasChanges)
        #expect(CoreDataTestHelpers.save(context))
        #expect(try body(on: fieldTrip, in: context) == "Morning:\nfield  trip TO the zoo, 9:00")
        #expect(tripPad.modifiedAt == padStamp)
        #expect(try body(on: pictureDay, in: context) == "PEACE assembly\n\nPE")
        #expect(CalendarNotePadCopy.isCopied(trip))
        #expect(CalendarNotePadCopy.isCopied(gym))
    }

    @Test("Whole-word matching, with spacing and case evened out")
    func padTextContains() {
        #expect(PadText.contains("Picture day", in: "Picture day, 9:00"))
        #expect(PadText.contains("picture   DAY", in: "Bring forms\nPicture\nday"))
        #expect(PadText.contains("(PE)", in: "Gym (PE) moved"))
        #expect(!PadText.contains("PE", in: "PEACE assembly"))
        #expect(!PadText.contains("Art", in: "Start the day"))
        #expect(!PadText.contains("Field trip", in: ""))
        #expect(PadText.contains("  ", in: "anything"))
    }

    // MARK: - Running again

    @Test("A second run adds nothing; a note un-marked again finds its text in the pad and only gets the mark back")
    func rerunIsANoOp() throws {
        let context = try CoreDataTestHelpers.makeContext()
        try pad("Call Maya's dad", on: fieldTrip, in: context)
        let trip = note("Field trip to the zoo", on: fieldTrip, in: context)
        let photos = note("Picture day", on: pictureDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 2))
        let first = try body(on: fieldTrip, in: context)
        let firstStamp = try pads(on: fieldTrip, in: context).first?.modifiedAt

        let again = CalendarNotePadCopy.run(in: context)
        #expect(again == CalendarNotePadCopy.Outcome())
        #expect(!context.hasChanges)

        // Both un-marked (as a restore from a backup made before the copy
        // leaves them): the pads are checked, and already have the text.
        for note in [trip, photos] { note.modifiedAt = note.createdAt }
        #expect(CoreDataTestHelpers.save(context))
        let checked = CalendarNotePadCopy.run(in: context)
        #expect(checked == CalendarNotePadCopy.Outcome(alreadyThere: 2))
        #expect(context.updatedObjects.allSatisfy { $0 is CDCalendarNote })
        #expect(context.insertedObjects.isEmpty)
        #expect(CoreDataTestHelpers.save(context))
        #expect(try body(on: fieldTrip, in: context) == first)
        #expect(try pads(on: fieldTrip, in: context).first?.modifiedAt == firstStamp)
        #expect(CalendarNotePadCopy.isCopied(trip))
        #expect(CalendarNotePadCopy.isCopied(photos))
    }

    @Test("A copied line she edits or deletes on the pad doesn't come back on the next launch")
    func editedPadLineStaysEdited() throws {
        let context = try CoreDataTestHelpers.makeContext()
        note("Picture day", on: pictureDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 1))

        let padForDay = try #require(try pads(on: pictureDay, in: context).first)
        padForDay.setBody("Photos moved to 11/2")
        #expect(CoreDataTestHelpers.save(context))

        #expect(copy(context) == CalendarNotePadCopy.Outcome())
        #expect(padForDay.body == "Photos moved to 11/2")
    }
}

// Outside the struct body only for SwiftLint's type length limit.
extension CalendarNotePadCopyTests {

    @Test("A pad open in an editor keeps the copied text when she saves her typing")
    func openEditorKeepsTheCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        try pad("Call Maya's dad", on: fieldTrip, in: context)
        note("Field trip to the zoo", on: fieldTrip, in: context)
        #expect(CoreDataTestHelpers.save(context))
        // Today's Pad opened on "Call Maya's dad" before the launch step ran.
        let base = "Call Maya's dad"
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 1))

        let day = try #require(fieldTrip.startOfDay())
        let saved = TodayDataFetcher.savePadText("Call Maya's dad at 3", base: base, day: day, context: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(saved.text.contains("Field trip to the zoo"))
        #expect(saved.text.contains("at 3"))
    }

    @Test("A new Mac, whose notes and pads arrive from iCloud together, doesn't put back a line she took off")
    func newMacKeepsTheLineOff() throws {
        // A fresh store: the note as the first Mac marked it, and the pad as
        // she left it after taking the copied line off.
        let newMac = try CoreDataTestHelpers.makeContext()
        let photos = marked(note("Picture day", on: pictureDay, in: newMac))
        let padForDay = try pad("Photos moved to 11/2", on: pictureDay, in: newMac)
        #expect(CoreDataTestHelpers.save(newMac))

        #expect(CalendarNotePadCopy.run(in: newMac) == CalendarNotePadCopy.Outcome())
        #expect(!newMac.hasChanges)
        #expect(padForDay.body == "Photos moved to 11/2")
        #expect(photos.modifiedAt == CalendarNotePadCopy.copiedMark)
        // Nor does the Calendar show it beside the pad.
        #expect(CalendarNotePadCopy.uncopiedTexts(of: [photos], padText: "Photos moved to 11/2").isEmpty)
    }

    // MARK: - Two devices

    @Test("Two devices that each copy before syncing end with the note in the day's pad once")
    func twoDevicesConverge() throws {
        let mac = try CoreDataTestHelpers.makeContext()
        let iPad = try CoreDataTestHelpers.makeContext()
        let noteID = UUID()
        for context in [mac, iPad] {
            note("Field trip to the zoo", on: fieldTrip, id: noteID, in: context)
            #expect(CoreDataTestHelpers.save(context))
        }
        #expect(copy(mac) == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(copy(iPad) == CalendarNotePadCopy.Outcome(copied: 1))

        // The iPad's pad arrives on the Mac, as a second row for the day.
        let iPadPad = try #require(try pads(on: fieldTrip, in: iPad).first)
        let arrived = try pad(
            iPadPad.body ?? "", on: fieldTrip, id: try #require(iPadPad.id), made: 120, in: mac
        )
        arrived.createdAt = iPadPad.createdAt
        #expect(CoreDataTestHelpers.save(mac))

        let day = try #require(fieldTrip.startOfDay())
        let joined = try #require(TodayDataFetcher.fetchDayPad(day: day, context: mac))
        #expect(CoreDataTestHelpers.save(mac))
        #expect(occurrences(of: "Field trip to the zoo", in: joined.body) == 1)
        #expect(try pads(on: fieldTrip, in: mac).count == 1)

        // And the Mac's next launch adds nothing.
        #expect(copy(mac) == CalendarNotePadCopy.Outcome())
        #expect(occurrences(of: "Field trip to the zoo", in: try body(on: fieldTrip, in: mac)) == 1)
    }

    @Test("A device that already has another's copy, synced in with its mark, writes nothing")
    func secondDeviceFindsTheCopy() throws {
        let iPad = try CoreDataTestHelpers.makeContext()
        // The Mac's copy, synced down: the pad from before plus the note, and
        // the note marked, both from the Mac's one save.
        try pad("Call Maya's dad\n\nField trip to the zoo", on: fieldTrip, in: iPad)
        marked(note("Field trip to the zoo", on: fieldTrip, in: iPad))
        #expect(CoreDataTestHelpers.save(iPad))

        #expect(CalendarNotePadCopy.run(in: iPad) == CalendarNotePadCopy.Outcome())
        #expect(!iPad.hasChanges)
    }

    @Test("Two devices appending to the same synced pad leave the same text")
    func sameSyncedPadConverges() throws {
        let mac = try CoreDataTestHelpers.makeContext()
        let iPad = try CoreDataTestHelpers.makeContext()
        let padID = UUID()
        let noteID = UUID()
        for context in [mac, iPad] {
            try pad("Call Maya's dad", on: fieldTrip, id: padID, in: context)
            note("Field trip to the zoo", on: fieldTrip, id: noteID, in: context)
            #expect(CoreDataTestHelpers.save(context))
        }
        #expect(copy(mac) == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(copy(iPad) == CalendarNotePadCopy.Outcome(copied: 1))
        let macBody = try body(on: fieldTrip, in: mac)
        #expect(macBody == "Call Maya's dad\n\nField trip to the zoo")
        #expect(try body(on: fieldTrip, in: iPad) == macBody)
    }

    // MARK: - Older builds

    @Test("A note an older build writes or edits later is copied on the next launch; the first isn't added again")
    func laterNoteFromAnOlderBuild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = note("Field trip to the zoo", on: fieldTrip, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(CalendarNotePadCopy.isCopied(first))

        // An iPad still on the old build adds a note the same day and another
        // day (new notes get the time as their `modifiedAt`)...
        note("Bring permission forms", on: fieldTrip, made: 3600, in: context)
        note("Picture day", on: pictureDay, made: 3600, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 2))
        #expect(try body(on: fieldTrip, in: context) == "Field trip to the zoo\n\nBring permission forms")
        #expect(try body(on: pictureDay, in: context) == "Picture day")

        // ...and changes the first one's text, stamping it with the time as its
        // Calendar does, which takes the mark off.
        first.text = "Field trip to the aquarium"
        first.modifiedAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        #expect(!CalendarNotePadCopy.isCopied(first))
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 1))
        let after = try body(on: fieldTrip, in: context)
        #expect(after == "Field trip to the zoo\n\nBring permission forms\n\nField trip to the aquarium")
        #expect(occurrences(of: "Bring permission forms", in: after) == 1)
        #expect(CalendarNotePadCopy.isCopied(first))
    }
}
