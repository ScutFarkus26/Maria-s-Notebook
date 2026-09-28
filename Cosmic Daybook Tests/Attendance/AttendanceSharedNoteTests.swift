import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The day's attendance note lives on the shared `AttendanceRecord` (schema 8)
/// so an assistant sees it. These pin that the store writes it there, that the
/// launch move carries the old private notes over without losing text, and
/// that merging duplicate records keeps both devices' notes.
@Suite("Shared attendance notes")
@MainActor
struct AttendanceSharedNoteTests {

    private func makeStudent(in context: NSManagedObjectContext) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = "Etty"
        student.lastName = "Example"
        return student
    }

    private func linkedNote(
        _ body: String, to record: CDAttendanceRecord, in context: NSManagedObjectContext
    ) -> CDNote {
        let note = CDNote(context: context)
        note.body = body
        note.attendanceRecordID = record.id?.uuidString
        return note
    }

    @Test("updateNote writes the record's note; empty text clears it; resetDay clears it")
    func storeWritesRecordNote() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent(in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: day))

        #expect(store.updateNote(record, to: "  Dentist, back by 11  "))
        #expect(record.note == "Dentist, back by 11")
        #expect(!store.updateNote(record, to: "Dentist, back by 11"))

        #expect(store.updateNote(record, to: "   "))
        #expect(record.note == nil)

        _ = store.updateNote(record, to: "Left at noon")
        _ = try store.resetDay(for: day, students: [student])
        #expect(record.note == nil)
    }

    @Test("The launch move carries linked private notes onto the record and deletes them")
    func moveCarriesNotes() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent(in: context)
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: AppCalendar.startOfDay(Date())))
        record.note = "Tired"
        let moved = linkedNote("Picked up early", to: record, in: context)
        let repeated = linkedNote("Tired", to: record, in: context)

        let orphan = CDNote(context: context)
        orphan.body = "Record long gone"
        orphan.attendanceRecordID = UUID().uuidString
        try context.save()

        #expect(AttendanceNoteMove.run(using: context) == 2)
        #expect(record.note == "Tired\nPicked up early")
        #expect(moved.isDeleted)
        #expect(repeated.isDeleted)
        #expect(!orphan.isDeleted)

        try context.save()
        #expect(AttendanceNoteMove.run(using: context) == 0)
    }

    @Test("Merging duplicate records keeps both notes")
    func dedupKeepsNotes() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent(in: context)
        let day = AppCalendar.startOfDay(Date())

        let first = CDAttendanceRecord(context: context)
        first.studentID = student.id?.uuidString ?? ""
        first.date = day
        first.status = .present
        first.note = "Arrived with a cold"
        first.modifiedAt = Date(timeIntervalSince1970: 1_000)

        let second = CDAttendanceRecord(context: context)
        second.studentID = first.studentID
        second.date = day
        second.status = .present
        second.note = "Went home after lunch"
        second.modifiedAt = Date(timeIntervalSince1970: 2_000)
        try context.save()

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 1)
        let survivor = try #require(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).first)
        let note = try #require(survivor.note)
        #expect(note.contains("Arrived with a cold"))
        #expect(note.contains("Went home after lunch"))
    }

    @Test("Merging notes drops empties and repeats")
    func mergedRules() {
        #expect(AttendanceNoteMove.merged(nil, nil) == nil)
        #expect(AttendanceNoteMove.merged("  ", "") == nil)
        #expect(AttendanceNoteMove.merged(nil, "a") == "a")
        #expect(AttendanceNoteMove.merged("a", nil) == "a")
        #expect(AttendanceNoteMove.merged("a b", "b") == "a b")
        #expect(AttendanceNoteMove.merged("a", "c") == "a\nc")
    }
}
