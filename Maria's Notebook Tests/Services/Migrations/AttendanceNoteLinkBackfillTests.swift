import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// The backfill fills Note.attendanceRecordID from the attendanceRecord
// relationship so the relationship can later be removed (attendance is moving
// to the shared store, and a relationship cannot cross store configurations).
@Suite("Attendance note-link backfill")
@MainActor
struct AttendanceNoteLinkBackfillTests {

    /// Runs `work` with the completion flag cleared, restoring it afterwards so
    /// these tests can't affect the app's own one-shot gating.
    private func withFlagCleared(_ work: () throws -> Void) rethrows {
        let key = UserDefaultsKeys.attendanceNoteLinkBackfillV1Complete
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        try work()
    }

    @Test("Backfill fills the FK from the relationship and is idempotent")
    func backfillFillsAndConverges() throws {
        try withFlagCleared {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let context = stack.viewContext

            let record = CDAttendanceRecord(context: context)
            record.studentID = UUID().uuidString
            record.date = AppCalendar.startOfDay(Date())

            let linked = CDNote(context: context)
            linked.body = "Linked via relationship only"
            linked.attendanceRecord = record
            linked.attendanceRecordID = nil

            let untouched = CDNote(context: context)
            untouched.body = "No attendance link"
            #expect(CoreDataTestHelpers.save(context))

            AttendanceNoteLinkBackfill.run(in: context)
            #expect(linked.attendanceRecordID == record.id?.uuidString)
            #expect(untouched.attendanceRecordID == nil)

            // Second pass finds nothing to do and leaves the values alone.
            AttendanceNoteLinkBackfill.run(in: context)
            #expect(linked.attendanceRecordID == record.id?.uuidString)
        }
    }

    @Test("A note whose FK is already set is not rewritten")
    func existingFKUntouched() throws {
        try withFlagCleared {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let context = stack.viewContext

            let record = CDAttendanceRecord(context: context)
            record.studentID = UUID().uuidString
            record.date = AppCalendar.startOfDay(Date())

            let preset = UUID().uuidString
            let note = CDNote(context: context)
            note.body = "FK already present"
            note.attendanceRecord = record
            note.attendanceRecordID = preset
            #expect(CoreDataTestHelpers.save(context))

            AttendanceNoteLinkBackfill.run(in: context)
            #expect(note.attendanceRecordID == preset)
        }
    }
}
