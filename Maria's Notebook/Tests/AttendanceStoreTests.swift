#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("AttendanceStore Tests")
@MainActor
struct AttendanceStoreTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            AttendanceRecord.self,
            Student.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeStudent(id: UUID = UUID(), firstName: String = "Test", lastName: String = "Student") -> Student {
        return Student(id: id, firstName: firstName, lastName: lastName)
    }

    // MARK: - loadOrCreateRecords Tests

    @Test("loadOrCreateRecords creates records for all students when none exist")
    func loadOrCreateRecordsCreatesAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let students = [
            makeStudent(firstName: "Alice", lastName: "Anderson"),
            makeStudent(firstName: "Bob", lastName: "Brown"),
            makeStudent(firstName: "Charlie", lastName: "Chen"),
        ]

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let result = try store.loadOrCreateRecords(for: date, students: students)

        #expect(result.records.count == 3)
        #expect(result.didInsert == true)

        // All should be unmarked by default
        for record in result.records {
            #expect(record.status == .unmarked)
            #expect(record.absenceReason == .none)
        }
    }

    @Test("loadOrCreateRecords returns existing records without creating duplicates")
    func loadOrCreateRecordsNoduplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let student1 = makeStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student1)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let normalizedDate = date.normalizedDay()

        // Create an existing record
        let existing = AttendanceRecord(studentID: student1.id, date: normalizedDate, status: .present)
        context.insert(existing)
        try context.save()

        // Load records again
        let result = try store.loadOrCreateRecords(for: date, students: [student1])

        #expect(result.records.count == 1)
        #expect(result.didInsert == false)
        #expect(result.records[0].status == .present) // Preserves existing status
    }

    @Test("loadOrCreateRecords creates only missing records")
    func loadOrCreateRecordsPartial() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let student1 = makeStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeStudent(firstName: "Bob", lastName: "Brown")

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let normalizedDate = date.normalizedDay()

        // Create record for student1 only
        let existing = AttendanceRecord(studentID: student1.id, date: normalizedDate, status: .present)
        context.insert(existing)
        try context.save()

        // Load records for both students
        let result = try store.loadOrCreateRecords(for: date, students: [student1, student2])

        #expect(result.records.count == 2)
        #expect(result.didInsert == true)

        // Find student2's new record
        let student2Record = result.records.first { $0.studentID == student2.id.uuidString }
        #expect(student2Record != nil)
        #expect(student2Record?.status == .unmarked)
    }

    @Test("loadOrCreateRecords normalizes dates correctly")
    func loadOrCreateRecordsNormalizesDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let student = makeStudent(firstName: "Alice", lastName: "Anderson")

        // Use different times of day - should all normalize to same day
        let morning = TestCalendar.date(year: 2025, month: 1, day: 15, hour: 8, minute: 30)
        let afternoon = TestCalendar.date(year: 2025, month: 1, day: 15, hour: 14, minute: 45)

        let result1 = try store.loadOrCreateRecords(for: morning, students: [student])
        #expect(result1.didInsert == true)

        let result2 = try store.loadOrCreateRecords(for: afternoon, students: [student])
        #expect(result2.didInsert == false) // Should find existing record

        #expect(result1.records.count == 1)
        #expect(result2.records.count == 1)
    }

    @Test("loadOrCreateRecords handles duplicate records gracefully")
    func loadOrCreateRecordsHandlesDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let student = makeStudent(firstName: "Alice", lastName: "Anderson")

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let normalizedDate = date.normalizedDay()

        // Manually create duplicate records (shouldn't happen, but testing robustness)
        let record1 = AttendanceRecord(studentID: student.id, date: normalizedDate, status: .present)
        let record2 = AttendanceRecord(studentID: student.id, date: normalizedDate, status: .absent)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        // Should handle gracefully - uses first occurrence
        let result = try store.loadOrCreateRecords(for: date, students: [student])

        #expect(result.didInsert == false)
        // Should not crash, returns at least one record
        #expect(result.records.count >= 1)
    }

    @Test("loadOrCreateRecords with empty student list")
    func loadOrCreateRecordsEmptyStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let result = try store.loadOrCreateRecords(for: date, students: [])

        #expect(result.records.isEmpty)
        #expect(result.didInsert == false)
    }

    // MARK: - updateStatus Tests

    @Test("updateStatus changes status and returns true")
    func updateStatusChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(
            studentID: UUID(),
            date: Date(),
            status: .unmarked
        )
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateStatus(record, to: .present)

        #expect(changed == true)
        #expect(record.status == .present)
    }

    @Test("updateStatus clears absence reason when not absent")
    func updateStatusClearsAbsenceReason() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(
            studentID: UUID(),
            date: Date(),
            status: .absent,
            absenceReason: .sick
        )
        context.insert(record)

        let store = AttendanceStore(context: context)
        store.updateStatus(record, to: .present)

        #expect(record.status == .present)
        #expect(record.absenceReason == .none)
    }

    @Test("updateStatus returns false when status unchanged")
    func updateStatusUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(
            studentID: UUID(),
            date: Date(),
            status: .present
        )
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateStatus(record, to: .present)

        #expect(changed == false)
    }

    // MARK: - updateNote Tests

    @Test("updateNote sets note and returns true")
    func updateNoteChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(studentID: UUID(), date: Date())
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateNote(record, to: "Student arrived late")

        #expect(changed == true)
        #expect(record.note == "Student arrived late")
    }

    @Test("updateNote trims whitespace")
    func updateNoteTrimming() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(studentID: UUID(), date: Date())
        context.insert(record)

        let store = AttendanceStore(context: context)
        store.updateNote(record, to: "  Note with spaces  ")

        #expect(record.note == "Note with spaces")
    }

    @Test("updateNote converts empty string to nil")
    func updateNoteEmptyToNil() throws {
        let container = try makeContainer()
        let context = ModelContext(context)

        let record = AttendanceRecord(studentID: UUID(), date: Date(), note: "Original note")
        context.insert(record)

        let store = AttendanceStore(context: context)
        store.updateNote(record, to: "   ")

        #expect(record.note == nil)
    }

    @Test("updateNote returns false when unchanged")
    func updateNoteUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(studentID: UUID(), date: Date(), note: "Same note")
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateNote(record, to: "Same note")

        #expect(changed == false)
    }

    // MARK: - updateAbsenceReason Tests

    @Test("updateAbsenceReason changes reason when absent")
    func updateAbsenceReasonWhenAbsent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(
            studentID: UUID(),
            date: Date(),
            status: .absent,
            absenceReason: .none
        )
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateAbsenceReason(record, to: .sick)

        #expect(changed == true)
        #expect(record.absenceReason == .sick)
    }

    @Test("updateAbsenceReason returns false when not absent")
    func updateAbsenceReasonNotAbsent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(
            studentID: UUID(),
            date: Date(),
            status: .present
        )
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateAbsenceReason(record, to: .sick)

        #expect(changed == false)
        #expect(record.absenceReason == .none)
    }

    @Test("updateAbsenceReason returns false when unchanged")
    func updateAbsenceReasonUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = AttendanceRecord(
            studentID: UUID(),
            date: Date(),
            status: .absent,
            absenceReason: .vacation
        )
        context.insert(record)

        let store = AttendanceStore(context: context)
        let changed = store.updateAbsenceReason(record, to: .vacation)

        #expect(changed == false)
    }

    // MARK: - markAllPresent Tests

    @Test("markAllPresent marks all students as present")
    func markAllPresentSetsStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let students = [
            makeStudent(firstName: "Alice", lastName: "Anderson"),
            makeStudent(firstName: "Bob", lastName: "Brown"),
        ]

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let records = try store.markAllPresent(for: date, students: students)

        #expect(records.count == 2)
        for record in records {
            #expect(record.status == .present)
        }
    }

    @Test("markAllPresent overwrites existing statuses")
    func markAllPresentOverwrites() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let student = makeStudent(firstName: "Alice", lastName: "Anderson")
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let normalizedDate = date.normalizedDay()

        // Create record with absent status
        let existing = AttendanceRecord(studentID: student.id, date: normalizedDate, status: .absent, absenceReason: .sick)
        context.insert(existing)
        try context.save()

        let records = try store.markAllPresent(for: date, students: [student])

        #expect(records.count == 1)
        #expect(records[0].status == .present)
        #expect(records[0].absenceReason == .none) // Should be cleared
    }

    // MARK: - resetDay Tests

    @Test("resetDay resets all records to unmarked")
    func resetDaySetsUnmarked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let students = [
            makeStudent(firstName: "Alice", lastName: "Anderson"),
            makeStudent(firstName: "Bob", lastName: "Brown"),
        ]

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        // First mark all present
        _ = try store.markAllPresent(for: date, students: students)

        // Then reset
        let records = try store.resetDay(for: date, students: students)

        #expect(records.count == 2)
        for record in records {
            #expect(record.status == .unmarked)
            #expect(record.note == nil)
            #expect(record.absenceReason == .none)
        }
    }

    @Test("resetDay clears notes and absence reasons")
    func resetDayClearsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let student = makeStudent(firstName: "Alice", lastName: "Anderson")
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let normalizedDate = date.normalizedDay()

        // Create record with data
        let existing = AttendanceRecord(
            studentID: student.id,
            date: normalizedDate,
            status: .absent,
            absenceReason: .sick,
            note: "Called in sick"
        )
        context.insert(existing)
        try context.save()

        let records = try store.resetDay(for: date, students: [student])

        #expect(records.count == 1)
        #expect(records[0].status == .unmarked)
        #expect(records[0].note == nil)
        #expect(records[0].absenceReason == .none)
    }

    // MARK: - Integration Tests

    @Test("Complete attendance workflow")
    func completeWorkflow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AttendanceStore(context: context)

        let students = [
            makeStudent(firstName: "Alice", lastName: "Anderson"),
            makeStudent(firstName: "Bob", lastName: "Brown"),
            makeStudent(firstName: "Charlie", lastName: "Chen"),
        ]

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        // 1. Load initial records - all unmarked
        let initial = try store.loadOrCreateRecords(for: date, students: students)
        #expect(initial.records.count == 3)
        #expect(initial.didInsert == true)

        // 2. Mark all present
        _ = try store.markAllPresent(for: date, students: students)

        // 3. Mark one student absent with reason
        let aliceRecord = initial.records.first { rec in
            students.first { $0.id.uuidString == rec.studentID }?.firstName == "Alice"
        }
        #expect(aliceRecord != nil)
        store.updateStatus(aliceRecord!, to: .absent)
        store.updateAbsenceReason(aliceRecord!, to: .sick)
        store.updateNote(aliceRecord!, to: "Called in sick this morning")

        // 4. Verify final state
        let final = try store.loadOrCreateRecords(for: date, students: students)
        #expect(final.didInsert == false)

        let aliceFinal = final.records.first { rec in
            students.first { $0.id.uuidString == rec.studentID }?.firstName == "Alice"
        }
        #expect(aliceFinal?.status == .absent)
        #expect(aliceFinal?.absenceReason == .sick)
        #expect(aliceFinal?.note == "Called in sick this morning")

        let othersPresent = final.records.filter { $0.status == .present }
        #expect(othersPresent.count == 2)
    }
}

#endif
