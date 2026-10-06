import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #5. The one-line note fields on a check-in, a
// project work row and a project session save through `setLegacyNoteText`,
// which writes the record's one field note (`reportedBy == legacyField`).
// They started from `latestUnifiedNoteText`, the newest note of any kind, so
// a record with an observation newer than its field note showed the
// observation in the field, and saving it, even unchanged, overwrote the
// field note with the observation's words (clearing it deleted the field
// note). The fields now start from `legacyNoteText`, the field note itself;
// `latestUnifiedNoteText` stays what the rows display.

@Suite("Note fields edit their own field note")
@MainActor
struct LegacyNoteFieldEditTests {

    /// An observation filed on the record after its field note.
    private func observation(_ body: String, in context: NSManagedObjectContext) -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        note.updatedAt = Date().addingTimeInterval(3_600)
        return note
    }

    private func fieldNotes(in context: NSManagedObjectContext) -> [String] {
        context.safeFetch(CDFetchRequest(CDNote.self))
            .filter { $0.reportedBy == LegacyNoteFieldConstants.reporter }
            .map(\.body)
    }

    @Test("A check-in's field shows its field note, and saving it back unchanged changes nothing")
    func checkInFieldReadsTheFieldNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), in: context)
        checkIn.setLegacyNoteText("Bring the bead frame", in: context)
        observation("Counted to a thousand alone", in: context).workCheckIn = checkIn
        #expect(CoreDataTestHelpers.save(context))

        // What the rows show is unchanged.
        #expect(checkIn.latestUnifiedNoteText == "Counted to a thousand alone")
        #expect(checkIn.legacyNoteText == "Bring the bead frame")

        // The edit alert's round trip, as WorkDetailView makes it.
        #expect(!checkIn.setLegacyNoteText(checkIn.legacyNoteText, in: context))
        #expect(fieldNotes(in: context) == ["Bring the bead frame"])
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).count == 2)
    }

    @Test("With no field note the field starts empty, and clearing it leaves the observation")
    func emptyFieldLeavesObservations() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), in: context)
        observation("Needs the long multiplication card", in: context).workCheckIn = checkIn
        #expect(CoreDataTestHelpers.save(context))

        #expect(checkIn.legacyNoteText.isEmpty)
        #expect(!checkIn.setLegacyNoteText(nil, in: context))
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).map(\.body) == ["Needs the long multiplication card"])
    }

    @Test("A project work row's field and a session's notes read their own field notes")
    func projectFieldsReadTheirFieldNotes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Fundamental Needs poster")
        work.setLegacyNoteText("Find three pictures of shelter", in: context)
        observation("Chose igloos", in: context).work = work

        let session = CDProjectSession(context: context)
        session.setLegacyNoteText("Read chapter two first", in: context)
        observation("Everyone finished early", in: context).projectSession = session
        #expect(CoreDataTestHelpers.save(context))

        #expect(work.legacyNoteText == "Find three pictures of shelter")
        #expect(work.latestUnifiedNoteText == "Chose igloos")
        #expect(session.legacyNoteText == "Read chapter two first")
        #expect(session.latestUnifiedNoteText == "Everyone finished early")

        // An edit replaces the field note only.
        #expect(work.setLegacyNoteText("Find four pictures of shelter", in: context))
        #expect(CoreDataTestHelpers.save(context))
        #expect(Set(fieldNotes(in: context)) == ["Find four pictures of shelter", "Read chapter two first"])
        #expect(work.latestUnifiedNoteText == "Chose igloos")
    }
}
