#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("AttendanceRepository Fetch Tests", .serialized)
@MainActor
struct AttendanceRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("fetchRecord returns record by ID")
    func fetchRecordReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let record = makeTestAttendanceRecord(studentID: studentID, date: date, status: .present)
        context.insert(record)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecord(id: record.id)

        #expect(fetched != nil)
        #expect(fetched?.id == record.id)
        #expect(fetched?.status == .present)
    }

    @Test("fetchRecord returns nil for missing ID")
    func fetchRecordReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecord(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchRecords returns all when no predicate")
    func fetchRecordsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record1 = makeTestAttendanceRecord(studentID: studentID, date: TestCalendar.date(year: 2025, month: 1, day: 15))
        let record2 = makeTestAttendanceRecord(studentID: studentID, date: TestCalendar.date(year: 2025, month: 1, day: 16))
        let record3 = makeTestAttendanceRecord(studentID: studentID, date: TestCalendar.date(year: 2025, month: 1, day: 17))
        context.insert(record1)
        context.insert(record2)
        context.insert(record3)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecords()

        #expect(fetched.count == 3)
    }

    @Test("fetchRecords sorts by date descending by default")
    func fetchRecordsSortsByDateDesc() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 10)
        let newDate = TestCalendar.date(year: 2025, month: 1, day: 20)

        let record1 = makeTestAttendanceRecord(studentID: studentID, date: oldDate)
        let record2 = makeTestAttendanceRecord(studentID: studentID, date: newDate)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecords()

        #expect(fetched[0].date > fetched[1].date)
    }

    @Test("fetchRecords forDate filters correctly")
    func fetchRecordsForDateFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let targetDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let otherDate = TestCalendar.date(year: 2025, month: 1, day: 16)

        let record1 = makeTestAttendanceRecord(studentID: studentID, date: targetDate)
        let record2 = makeTestAttendanceRecord(studentID: studentID, date: otherDate)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecords(forDate: targetDate)

        #expect(fetched.count == 1)
        expectSameDay(fetched[0].date, targetDate)
    }

    @Test("fetchRecords forStudentID filters correctly")
    func fetchRecordsForStudentIDFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID1 = UUID()
        let studentID2 = UUID()
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        let record1 = makeTestAttendanceRecord(studentID: studentID1, date: date)
        let record2 = makeTestAttendanceRecord(studentID: studentID2, date: date)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecords(forStudentID: studentID1)

        #expect(fetched.count == 1)
        #expect(fetched[0].studentID == studentID1.uuidString)
    }

    @Test("fetchRecords handles empty database")
    func fetchRecordsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = AttendanceRepository(context: context)
        let fetched = repository.fetchRecords()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("AttendanceRepository Create Tests", .serialized)
@MainActor
struct AttendanceRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("createRecord creates record with required fields")
    func createRecordCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        let repository = AttendanceRepository(context: context)
        let record = repository.createRecord(studentID: studentID, date: date)

        #expect(record.studentID == studentID.uuidString)
        expectSameDay(record.date, date)
        #expect(record.status == .unmarked) // Default
        #expect(record.absenceReason == .none) // Default
    }

    @Test("createRecord sets optional fields when provided")
    func createRecordSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        let repository = AttendanceRepository(context: context)
        let record = repository.createRecord(
            studentID: studentID,
            date: date,
            status: .absent,
            absenceReason: .sick,
            note: "Had a cold"
        )

        #expect(record.status == .absent)
        #expect(record.absenceReason == .sick)
        #expect(record.latestUnifiedNoteText == "Had a cold")
    }

    @Test("createRecord normalizes date to start of day")
    func createRecordNormalizesDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        // Date with time component
        let dateWithTime = TestCalendar.date(year: 2025, month: 1, day: 15, hour: 14, minute: 30, second: 0)

        let repository = AttendanceRepository(context: context)
        let record = repository.createRecord(studentID: studentID, date: dateWithTime)

        // Should be normalized to start of day
        let startOfDay = Calendar.current.startOfDay(for: dateWithTime)
        #expect(record.date == startOfDay)
    }

    @Test("createRecord persists to context")
    func createRecordPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        let repository = AttendanceRepository(context: context)
        let record = repository.createRecord(studentID: studentID, date: date)

        let fetched = repository.fetchRecord(id: record.id)

        #expect(fetched != nil)
        #expect(fetched?.id == record.id)
    }
}

// MARK: - Update Tests

@Suite("AttendanceRepository Update Tests", .serialized)
@MainActor
struct AttendanceRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("updateStatus updates record status")
    func updateStatusUpdatesRecordStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, status: .unmarked)
        context.insert(record)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let result = repository.updateStatus(id: record.id, status: .present)

        #expect(result == true)
        #expect(record.status == .present)
    }

    @Test("updateStatus returns false for missing ID")
    func updateStatusReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = AttendanceRepository(context: context)
        let result = repository.updateStatus(id: UUID(), status: .present)

        #expect(result == false)
    }

    @Test("updateNote updates record note")
    func updateNoteUpdatesRecordNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, note: nil)
        context.insert(record)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let result = repository.updateNote(id: record.id, note: "Arrived late")

        #expect(result == true)
        #expect(record.latestUnifiedNoteText == "Arrived late")
    }

    @Test("updateNote clears note when nil provided")
    func updateNoteClearsNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, note: nil)
        context.insert(record)
        _ = record.setLegacyNoteText("Some note", in: context)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let result = repository.updateNote(id: record.id, note: nil)

        #expect(result == true)
        #expect(record.latestUnifiedNoteText.isEmpty)
    }

    @Test("updateAbsenceReason updates record reason")
    func updateAbsenceReasonUpdatesRecordReason() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, status: .absent, absenceReason: .none)
        context.insert(record)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let result = repository.updateAbsenceReason(id: record.id, reason: .sick)

        #expect(result == true)
        #expect(record.absenceReason == .sick)
    }
}

// MARK: - Bulk Operations Tests

@Suite("AttendanceRepository Bulk Operations Tests", .serialized)
@MainActor
struct AttendanceRepositoryBulkOperationsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("loadOrCreateRecords creates records for students without existing records")
    func loadOrCreateRecordsCreatesNewRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        let repository = AttendanceRepository(context: context)
        let (records, didInsert) = repository.loadOrCreateRecords(forDate: date, students: [student1, student2])

        #expect(records.count == 2)
        #expect(didInsert == true)
    }

    @Test("loadOrCreateRecords returns existing records without creating duplicates")
    func loadOrCreateRecordsReturnsExisting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let existingRecord = makeTestAttendanceRecord(studentID: student.id, date: date, status: .present)
        context.insert(existingRecord)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let (records, didInsert) = repository.loadOrCreateRecords(forDate: date, students: [student])

        #expect(records.count == 1)
        #expect(didInsert == false)
        #expect(records[0].status == .present) // Should be the existing record
    }

    @Test("markAllPresent marks all students present for a date")
    func markAllPresentMarksAllStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        let repository = AttendanceRepository(context: context)
        let records = repository.markAllPresent(forDate: date, students: [student1, student2])

        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.status == .present })
    }

    @Test("resetDay resets all records to unmarked")
    func resetDayResetsAllRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let record1 = makeTestAttendanceRecord(studentID: student1.id, date: date, status: .present)
        let record2 = makeTestAttendanceRecord(studentID: student2.id, date: date, status: .absent)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let repository = AttendanceRepository(context: context)
        let records = repository.resetDay(forDate: date, students: [student1, student2])

        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.status == .unmarked })
    }
}

// MARK: - Delete Tests

@Suite("AttendanceRepository Delete Tests", .serialized)
@MainActor
struct AttendanceRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("deleteRecord removes record from context")
    func deleteRecordRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID)
        context.insert(record)
        try context.save()

        let recordID = record.id

        let repository = AttendanceRepository(context: context)
        try repository.deleteRecord(id: recordID)

        let fetched = repository.fetchRecord(id: recordID)
        #expect(fetched == nil)
    }

    @Test("deleteRecord does nothing for missing ID")
    func deleteRecordDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = AttendanceRepository(context: context)
        try repository.deleteRecord(id: UUID())

        // Should not throw - just silently does nothing
    }
}

#endif
