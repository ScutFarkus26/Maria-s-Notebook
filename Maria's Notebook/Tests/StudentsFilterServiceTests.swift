#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - StudentsFilterService Hidden Test Students Tests

@Suite("StudentsFilterService Hidden Test Students Tests", .serialized)
@MainActor
struct StudentsFilterServiceHiddenTestStudentsTests {

    @Test("computeHiddenTestStudentIDs returns empty when showTestStudents is true")
    func returnsEmptyWhenShowTestStudentsTrue() {
        let students = [
            makeTestStudent(firstName: "Test", lastName: "Student"),
            makeTestStudent(firstName: "Alice", lastName: "Real"),
        ]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: true,
            testStudentNamesRaw: "test student"
        )

        #expect(result.isEmpty)
    }

    @Test("computeHiddenTestStudentIDs hides matching students when showTestStudents is false")
    func hidesMatchingStudents() {
        let testStudent = makeTestStudent(firstName: "Test", lastName: "Student")
        let realStudent = makeTestStudent(firstName: "Alice", lastName: "Real")
        let students = [testStudent, realStudent]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "test student"
        )

        #expect(result.contains(testStudent.id))
        #expect(!result.contains(realStudent.id))
    }

    @Test("computeHiddenTestStudentIDs handles comma-separated names")
    func handlesCommaSeparatedNames() {
        let test1 = makeTestStudent(firstName: "Test", lastName: "One")
        let test2 = makeTestStudent(firstName: "Demo", lastName: "User")
        let real = makeTestStudent(firstName: "Alice", lastName: "Real")
        let students = [test1, test2, real]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "test one, demo user"
        )

        #expect(result.contains(test1.id))
        #expect(result.contains(test2.id))
        #expect(!result.contains(real.id))
    }

    @Test("computeHiddenTestStudentIDs handles semicolon-separated names")
    func handlesSemicolonSeparatedNames() {
        let test1 = makeTestStudent(firstName: "Test", lastName: "One")
        let test2 = makeTestStudent(firstName: "Demo", lastName: "User")
        let students = [test1, test2]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "test one; demo user"
        )

        #expect(result.contains(test1.id))
        #expect(result.contains(test2.id))
    }

    @Test("computeHiddenTestStudentIDs handles newline-separated names")
    func handlesNewlineSeparatedNames() {
        let test1 = makeTestStudent(firstName: "Test", lastName: "One")
        let test2 = makeTestStudent(firstName: "Demo", lastName: "User")
        let students = [test1, test2]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "test one\ndemo user"
        )

        #expect(result.contains(test1.id))
        #expect(result.contains(test2.id))
    }

    @Test("computeHiddenTestStudentIDs is case insensitive")
    func isCaseInsensitive() {
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        let students = [student]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "TEST STUDENT"
        )

        #expect(result.contains(student.id))
    }

    @Test("computeHiddenTestStudentIDs trims whitespace from names")
    func trimsWhitespace() {
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        let students = [student]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "  test student  ,  "
        )

        #expect(result.contains(student.id))
    }

    @Test("computeHiddenTestStudentIDs returns empty for empty raw string")
    func returnsEmptyForEmptyRawString() {
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        let students = [student]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: ""
        )

        #expect(result.isEmpty)
    }

    @Test("computeHiddenTestStudentIDs returns empty for whitespace-only raw string")
    func returnsEmptyForWhitespaceOnlyRawString() {
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        let students = [student]

        let result = StudentsFilterService.computeHiddenTestStudentIDs(
            students: students,
            showTestStudents: false,
            testStudentNamesRaw: "   ,  , "
        )

        #expect(result.isEmpty)
    }
}

// MARK: - StudentsFilterService Present Now Tests

@Suite("StudentsFilterService Present Now Tests", .serialized)
@MainActor
struct StudentsFilterServicePresentNowTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
        ])
    }

    @Test("computePresentNowIDs returns present students")
    func returnsPresentStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "A")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "B")
        context.insert(student1)
        context.insert(student2)

        let today = Calendar.current.startOfDay(for: Date())
        let record1 = makeTestAttendanceRecord(studentID: student1.id, date: today, status: .present)
        let record2 = makeTestAttendanceRecord(studentID: student2.id, date: today, status: .absent)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let result = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: [record1, record2],
            hiddenTestStudentIDs: []
        )

        #expect(result.contains(student1.id))
        #expect(!result.contains(student2.id))
    }

    @Test("computePresentNowIDs includes tardy students as present")
    func includesTardyStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Charlie", lastName: "C")
        context.insert(student)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeTestAttendanceRecord(studentID: student.id, date: today, status: .tardy)
        context.insert(record)
        try context.save()

        let result = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: [record],
            hiddenTestStudentIDs: []
        )

        #expect(result.contains(student.id))
    }

    @Test("computePresentNowIDs excludes hidden test students")
    func excludesHiddenTestStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testStudent = makeTestStudent(firstName: "Test", lastName: "Student")
        let realStudent = makeTestStudent(firstName: "Alice", lastName: "Real")
        context.insert(testStudent)
        context.insert(realStudent)

        let today = Calendar.current.startOfDay(for: Date())
        let record1 = makeTestAttendanceRecord(studentID: testStudent.id, date: today, status: .present)
        let record2 = makeTestAttendanceRecord(studentID: realStudent.id, date: today, status: .present)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let result = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: [record1, record2],
            hiddenTestStudentIDs: [testStudent.id]
        )

        #expect(!result.contains(testStudent.id))
        #expect(result.contains(realStudent.id))
    }

    @Test("computePresentNowIDs ignores records from other days")
    func ignoresRecordsFromOtherDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "A")
        context.insert(student)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let record = makeTestAttendanceRecord(studentID: student.id, date: yesterday, status: .present)
        context.insert(record)
        try context.save()

        let result = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: [record],
            hiddenTestStudentIDs: []
        )

        #expect(result.isEmpty)
    }

    @Test("computePresentNowIDs returns empty for no records")
    func returnsEmptyForNoRecords() {
        let result = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: [],
            hiddenTestStudentIDs: []
        )

        #expect(result.isEmpty)
    }

    @Test("computePresentNowIDs excludes unmarked students")
    func excludesUnmarkedStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "A")
        context.insert(student)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeTestAttendanceRecord(studentID: student.id, date: today, status: .unmarked)
        context.insert(record)
        try context.save()

        let result = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: [record],
            hiddenTestStudentIDs: []
        )

        #expect(result.isEmpty)
    }
}

// MARK: - StudentsFilterService Integration Tests

@Suite("StudentsFilterService Integration Tests", .serialized)
@MainActor
struct StudentsFilterServiceIntegrationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
        ])
    }

    @Test("Full filtering workflow")
    func fullFilteringWorkflow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create a mix of students
        let testStudent = makeTestStudent(firstName: "Test", lastName: "Student")
        let alice = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let bob = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let charlie = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(testStudent)
        context.insert(alice)
        context.insert(bob)
        context.insert(charlie)

        // Create today's attendance
        let today = Calendar.current.startOfDay(for: Date())
        let testRecord = makeTestAttendanceRecord(studentID: testStudent.id, date: today, status: .present)
        let aliceRecord = makeTestAttendanceRecord(studentID: alice.id, date: today, status: .present)
        let bobRecord = makeTestAttendanceRecord(studentID: bob.id, date: today, status: .tardy)
        let charlieRecord = makeTestAttendanceRecord(studentID: charlie.id, date: today, status: .absent)
        context.insert(testRecord)
        context.insert(aliceRecord)
        context.insert(bobRecord)
        context.insert(charlieRecord)
        try context.save()

        let allStudents = [testStudent, alice, bob, charlie]
        let allRecords = [testRecord, aliceRecord, bobRecord, charlieRecord]

        // Step 1: Compute hidden test student IDs
        let hiddenIDs = StudentsFilterService.computeHiddenTestStudentIDs(
            students: allStudents,
            showTestStudents: false,
            testStudentNamesRaw: "test student"
        )

        #expect(hiddenIDs.count == 1)
        #expect(hiddenIDs.contains(testStudent.id))

        // Step 2: Compute present now IDs (excluding hidden)
        let presentIDs = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: allRecords,
            hiddenTestStudentIDs: hiddenIDs
        )

        // Should include Alice (present) and Bob (tardy), but not Test Student or Charlie
        #expect(presentIDs.count == 2)
        #expect(presentIDs.contains(alice.id))
        #expect(presentIDs.contains(bob.id))
        #expect(!presentIDs.contains(testStudent.id))
        #expect(!presentIDs.contains(charlie.id))
    }

    @Test("Filtering with showTestStudents enabled")
    func filteringWithShowTestStudentsEnabled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testStudent = makeTestStudent(firstName: "Test", lastName: "Student")
        let alice = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(testStudent)
        context.insert(alice)

        let today = Calendar.current.startOfDay(for: Date())
        let testRecord = makeTestAttendanceRecord(studentID: testStudent.id, date: today, status: .present)
        let aliceRecord = makeTestAttendanceRecord(studentID: alice.id, date: today, status: .present)
        context.insert(testRecord)
        context.insert(aliceRecord)
        try context.save()

        let allStudents = [testStudent, alice]
        let allRecords = [testRecord, aliceRecord]

        // With showTestStudents = true, no one should be hidden
        let hiddenIDs = StudentsFilterService.computeHiddenTestStudentIDs(
            students: allStudents,
            showTestStudents: true,
            testStudentNamesRaw: "test student"
        )

        #expect(hiddenIDs.isEmpty)

        let presentIDs = StudentsFilterService.computePresentNowIDs(
            attendanceRecords: allRecords,
            hiddenTestStudentIDs: hiddenIDs
        )

        // Both should be present
        #expect(presentIDs.count == 2)
        #expect(presentIDs.contains(testStudent.id))
        #expect(presentIDs.contains(alice.id))
    }
}

#endif
