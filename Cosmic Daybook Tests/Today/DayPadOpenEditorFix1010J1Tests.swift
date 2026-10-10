import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Review round of the 2026-10-10 fixes: a Day Pad left open (the Mac sits on
/// Today) saved its old text over a body another device had joined, typed into
/// a copy the join had deleted, or made a second pad for a day that had one
/// sync in after the editor opened empty.
@Suite("Day Pad saves from an open editor (fix 10-10 J1 review)")
@MainActor
struct DayPadOpenEditorFix1010J1Tests {

    private var day: Date { AppCalendar.startOfDay(Date(timeIntervalSince1970: 1_791_460_800)) }

    private func pads(in context: NSManagedObjectContext) -> [CDDayPad] {
        context.safeFetch(CDFetchRequest(CDDayPad.self)).filter { !$0.isDeleted }
    }

    @Test("Typing after another device joined the pad keeps the joined text and adds hers")
    func typingAfterJoinKeepsJoinedText() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let pad = CDDayPad(context: context, day: day)
        pad.body = "Mac note."
        #expect(CoreDataTestHelpers.save(context))
        // Opened with "Mac note."; meanwhile the iPad's text was joined in.
        pad.body = "Mac note.\n\niPad note."
        #expect(CoreDataTestHelpers.save(context))

        let saved = TodayDataFetcher.savePadText(
            "Mac note. And one more thing.", base: "Mac note.", day: day, context: context
        )

        #expect(saved.text == "Mac note.\n\niPad note.\n\nAnd one more thing.")
        #expect(pads(in: context).count == 1)
        #expect(pads(in: context).first?.body == saved.text)
    }

    @Test("Typing into a copy the join deleted lands in the kept pad")
    func typingIntoDeletedCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let kept = CDDayPad(context: context, day: day)
        kept.body = "iPad note."
        kept.createdAt = day.addingTimeInterval(3600)
        let mine = CDDayPad(context: context, day: day)
        mine.body = "Mac note."
        mine.createdAt = day.addingTimeInterval(7200)
        #expect(CoreDataTestHelpers.save(context))

        let saved = TodayDataFetcher.savePadText(
            "Mac note.\nBring the globe.", base: "Mac note.", day: day, context: context
        )

        #expect(saved.pad === kept)
        #expect(mine.isDeleted || mine.managedObjectContext == nil)
        #expect(saved.text == "iPad note.\n\nMac note.\n\nBring the globe.")
        #expect(pads(in: context).count == 1)
    }

    @Test("An editor opened empty writes into a pad that synced in meanwhile")
    func emptyEditorFindsSyncedPad() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let synced = CDDayPad(context: context, day: day)
        synced.body = "From the iPad."
        #expect(CoreDataTestHelpers.save(context))

        let saved = TodayDataFetcher.savePadText("From the Mac.", base: "", day: day, context: context)

        #expect(saved.pad === synced)
        #expect(saved.text == "From the iPad.\n\nFrom the Mac.")
        #expect(pads(in: context).count == 1)
    }

    @Test("With nothing changed underneath, her text is saved as typed")
    func plainSave() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let pad = CDDayPad(context: context, day: day)
        pad.body = "Mac note."
        #expect(CoreDataTestHelpers.save(context))

        let saved = TodayDataFetcher.savePadText("Mac note, edited.", base: "Mac note.", day: day, context: context)

        #expect(saved.text == "Mac note, edited.")
        #expect(pad.body == "Mac note, edited.")
    }
}
