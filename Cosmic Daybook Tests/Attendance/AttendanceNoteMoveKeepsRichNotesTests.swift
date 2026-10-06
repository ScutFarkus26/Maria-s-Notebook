import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #53. The launch move folded every private Note
// linked to an attendance record into the record's text and deleted it.
// Before schema 8 those notes came from the general note editor, so some
// carry a photo, a link to a work or lesson, several children, or a
// follow-up flag, and the move kept only their words. Now only notes that
// are text alone move; the rest stay as Notes (still listed under Notes,
// marked Attendance).

@Suite("The attendance note move leaves notes that are more than text")
@MainActor
struct AttendanceNoteMoveKeepsRichNotesTests {

    private func setUp() throws -> (NSManagedObjectContext, CDAttendanceRecord) {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty")
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: AppCalendar.startOfDay(Date())))
        return (context, record)
    }

    private func linkedNote(
        _ body: String, to record: CDAttendanceRecord, in context: NSManagedObjectContext
    ) -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        note.attendanceRecordID = record.id?.uuidString
        return note
    }

    @Test("A note with a photo, a link, several children or a flag stays a Note; a plain one moves")
    func onlyPlainNotesMove() throws {
        let (context, record) = try setUp()
        let plain = linkedNote("Picked up at noon", to: record, in: context)
        plain.tagsArray = ["Attendance"]
        linkedNote("Wore the new glasses", to: record, in: context).imagePath = "glasses.jpg"
        linkedNote("Finished the bead frame first", to: record, in: context).work =
            CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        linkedNote("Call home about the fever", to: record, in: context).needsFollowUp = true
        let several = linkedNote("Came in together", to: record, in: context)
        several.scope = .students([UUID(), UUID()])
        several.syncStudentLinks(in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(AttendanceNoteMove.run(using: context) == 1)
        #expect(CoreDataTestHelpers.save(context))

        #expect(record.note == "Picked up at noon")
        let left = Set(context.safeFetch(CDFetchRequest(CDNote.self)).map(\.body))
        #expect(left == [
            "Wore the new glasses", "Finished the bead frame first", "Call home about the fever", "Came in together"
        ])
        // The next launch moves nothing more.
        #expect(AttendanceNoteMove.run(using: context) == 0)
    }
}
