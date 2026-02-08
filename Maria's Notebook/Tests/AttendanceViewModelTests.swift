#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Initialization Tests

@Suite("AttendanceViewModel Initialization Tests", .serialized)
@MainActor
struct AttendanceViewModelInitializationTests {

    @Test("AttendanceViewModel initializes with current date normalized")
    func initializesWithCurrentDateNormalized() {
        let now = Date()
        let vm = AttendanceViewModel(selectedDate: now)

        let expected = Calendar.current.startOfDay(for: now)
        #expect(vm.selectedDate == expected)
    }

    @Test("AttendanceViewModel recordsByStudentID starts empty")
    func recordsByStudentStartsEmpty() {
        let vm = AttendanceViewModel()

        #expect(vm.recordsByStudent.isEmpty)
    }

    @Test("AttendanceViewModel sortKey defaults to lastName")
    func sortKeyDefaultsToLastName() {
        let vm = AttendanceViewModel()

        #expect(vm.sortKey == .lastName)
    }

    @Test("AttendanceViewModel can be initialized with specific date")
    func initializesWithSpecificDate() {
        let date = TestCalendar.date(year: 2025, month: 3, day: 15)
        let vm = AttendanceViewModel(selectedDate: date)

        expectSameDay(vm.selectedDate, date)
    }
}

// MARK: - Sorting Tests

@Suite("AttendanceViewModel Sorting Tests", .serialized)
@MainActor
struct AttendanceViewModelSortingTests {

    @Test("sortedAndFiltered sorts by lastName correctly")
    func sortsByLastNameCorrectly() {
        let vm = AttendanceViewModel()
        vm.sortKey = .lastName

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Zebra"),
            makeTestStudent(firstName: "Bob", lastName: "Anderson"),
            makeTestStudent(firstName: "Charlie", lastName: "Miller"),
        ]

        let sorted = vm.sortedAndFiltered(students: students)

        #expect(sorted[0].lastName == "Anderson")
        #expect(sorted[1].lastName == "Miller")
        #expect(sorted[2].lastName == "Zebra")
    }

    @Test("sortedAndFiltered sorts by firstName correctly")
    func sortsByFirstNameCorrectly() {
        let vm = AttendanceViewModel()
        vm.sortKey = .firstName

        let students = [
            makeTestStudent(firstName: "Charlie", lastName: "Smith"),
            makeTestStudent(firstName: "Alice", lastName: "Jones"),
            makeTestStudent(firstName: "Bob", lastName: "Wilson"),
        ]

        let sorted = vm.sortedAndFiltered(students: students)

        #expect(sorted[0].firstName == "Alice")
        #expect(sorted[1].firstName == "Bob")
        #expect(sorted[2].firstName == "Charlie")
    }

    @Test("sortedAndFiltered handles same lastName with firstName tiebreaker")
    func handlesLastNameTiebreaker() {
        let vm = AttendanceViewModel()
        vm.sortKey = .lastName

        let students = [
            makeTestStudent(firstName: "Charlie", lastName: "Smith"),
            makeTestStudent(firstName: "Alice", lastName: "Smith"),
            makeTestStudent(firstName: "Bob", lastName: "Smith"),
        ]

        let sorted = vm.sortedAndFiltered(students: students)

        #expect(sorted[0].firstName == "Alice")
        #expect(sorted[1].firstName == "Bob")
        #expect(sorted[2].firstName == "Charlie")
    }

    @Test("sortedAndFiltered handles same firstName with lastName tiebreaker")
    func handlesFirstNameTiebreaker() {
        let vm = AttendanceViewModel()
        vm.sortKey = .firstName

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Zebra"),
            makeTestStudent(firstName: "Alice", lastName: "Anderson"),
            makeTestStudent(firstName: "Alice", lastName: "Miller"),
        ]

        let sorted = vm.sortedAndFiltered(students: students)

        #expect(sorted[0].lastName == "Anderson")
        #expect(sorted[1].lastName == "Miller")
        #expect(sorted[2].lastName == "Zebra")
    }

    @Test("sortedAndFiltered is case insensitive")
    func sortingIsCaseInsensitive() {
        let vm = AttendanceViewModel()
        vm.sortKey = .lastName

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "ZEBRA"),
            makeTestStudent(firstName: "Bob", lastName: "anderson"),
            makeTestStudent(firstName: "Charlie", lastName: "Miller"),
        ]

        let sorted = vm.sortedAndFiltered(students: students)

        #expect(sorted[0].lastName.lowercased() == "anderson")
        #expect(sorted[1].lastName.lowercased() == "miller")
        #expect(sorted[2].lastName.lowercased() == "zebra")
    }

    @Test("sortedAndFiltered handles empty array")
    func handlesEmptyArray() {
        let vm = AttendanceViewModel()

        let sorted = vm.sortedAndFiltered(students: [])

        #expect(sorted.isEmpty)
    }

    @Test("sortedAndFiltered handles single element")
    func handlesSingleElement() {
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Solo", lastName: "Student")

        let sorted = vm.sortedAndFiltered(students: [student])

        #expect(sorted.count == 1)
        #expect(sorted[0].firstName == "Solo")
    }
}

// MARK: - Status Cycling Tests

@Suite("AttendanceViewModel Status Cycling Tests", .serialized)
@MainActor
struct AttendanceViewModelStatusCyclingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("cycleStatus transitions unmarked to present")
    func cyclesUnmarkedToPresent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .unmarked)
        context.insert(record)

        vm.recordsByStudent[student.id.uuidString] = record

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.status == .present)
    }

    @Test("cycleStatus transitions present to absent")
    func cyclesPresentToAbsent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .present)
        context.insert(record)

        vm.recordsByStudent[student.id.uuidString] = record

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.status == .absent)
    }

    @Test("cycleStatus transitions absent to tardy")
    func cyclesAbsentToTardy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .absent)
        context.insert(record)

        vm.recordsByStudent[student.id.uuidString] = record

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.status == .tardy)
    }

    @Test("cycleStatus transitions tardy to leftEarly")
    func cyclesTardyToLeftEarly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .tardy)
        context.insert(record)

        vm.recordsByStudent[student.id.uuidString] = record

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.status == .leftEarly)
    }

    @Test("cycleStatus transitions leftEarly to present")
    func cyclesLeftEarlyToPresent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .leftEarly)
        context.insert(record)

        vm.recordsByStudent[student.id.uuidString] = record

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.status == .present)
    }

    @Test("cycleStatus does nothing for unknown student")
    func doesNothingForUnknownStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Unknown", lastName: "Student")
        // Don't add record to vm.recordsByStudent

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString] == nil)
    }
}

// MARK: - Loading Tests

@Suite("AttendanceViewModel Loading Tests", .serialized)
@MainActor
struct AttendanceViewModelLoadingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("load populates recordsByStudent")
    func loadPopulatesRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudent.count == 2)
        #expect(vm.recordsByStudent[student1.id.uuidString] != nil)
        #expect(vm.recordsByStudent[student2.id.uuidString] != nil)
    }

    @Test("load filters to provided students only")
    func loadFiltersToProvidedStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        // Create a record for student3 that shouldn't be included
        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let extraRecord = makeTestAttendanceRecord(studentID: student3.id, date: date)
        context.insert(extraRecord)

        vm.load(for: date, students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudent.count == 2)
        #expect(vm.recordsByStudent[student3.id.uuidString] == nil)
    }

    @Test("load handles empty student list")
    func loadHandlesEmptyStudentList() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [], modelContext: context)

        #expect(vm.recordsByStudent.isEmpty)
    }

    @Test("load updates selectedDate")
    func loadUpdatesSelectedDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let originalDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        vm.load(for: originalDate, students: [], modelContext: context)
        #expect(Calendar.current.component(.month, from: vm.selectedDate) == 1)

        vm.load(for: newDate, students: [], modelContext: context)
        #expect(Calendar.current.component(.month, from: vm.selectedDate) == 2)
    }

    @Test("load creates unmarked records for students without records")
    func loadCreatesUnmarkedRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "New", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.status == .unmarked)
    }
}

// MARK: - Stats Computation Tests

@Suite("AttendanceViewModel Stats Tests", .serialized)
@MainActor
struct AttendanceViewModelStatsTests {

    @Test("countPresent returns correct count")
    func countPresentReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.recordsByStudent[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .present)
        vm.recordsByStudent[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)
        vm.recordsByStudent[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .absent)

        #expect(vm.countPresent == 2)
    }

    @Test("countAbsent returns correct count")
    func countAbsentReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.recordsByStudent[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .absent)
        vm.recordsByStudent[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)
        vm.recordsByStudent[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .absent)

        #expect(vm.countAbsent == 2)
    }

    @Test("countTardy returns correct count")
    func countTardyReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()

        vm.recordsByStudent[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .tardy)
        vm.recordsByStudent[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)

        #expect(vm.countTardy == 1)
    }

    @Test("countLeftEarly returns correct count")
    func countLeftEarlyReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.recordsByStudent[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .leftEarly)
        vm.recordsByStudent[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .leftEarly)
        vm.recordsByStudent[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .leftEarly)

        #expect(vm.countLeftEarly == 3)
    }

    @Test("countUnmarked returns correct count")
    func countUnmarkedReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()

        vm.recordsByStudent[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .unmarked)
        vm.recordsByStudent[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)

        #expect(vm.countUnmarked == 1)
    }

    @Test("inClassCount sums present and tardy")
    func inClassCountSumsPresentAndTardy() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()

        vm.recordsByStudent[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .present)
        vm.recordsByStudent[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)
        vm.recordsByStudent[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .tardy)
        vm.recordsByStudent[id4.uuidString] = makeTestAttendanceRecord(studentID: id4, status: .absent)

        #expect(vm.inClassCount == 3)  // 2 present + 1 tardy
    }

    @Test("stats return zero for empty records")
    func statsReturnZeroForEmptyRecords() {
        let vm = AttendanceViewModel()

        #expect(vm.countPresent == 0)
        #expect(vm.countAbsent == 0)
        #expect(vm.countTardy == 0)
        #expect(vm.countLeftEarly == 0)
        #expect(vm.countUnmarked == 0)
        #expect(vm.inClassCount == 0)
    }
}

// MARK: - Actions Tests

@Suite("AttendanceViewModel Actions Tests", .serialized)
@MainActor
struct AttendanceViewModelActionsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("markAllPresent updates all records to present")
    func markAllPresentUpdatesAllRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student1, student2], modelContext: context)

        // Verify initial state is unmarked
        #expect(vm.recordsByStudent[student1.id.uuidString]?.status == .unmarked)
        #expect(vm.recordsByStudent[student2.id.uuidString]?.status == .unmarked)

        vm.markAllPresent(students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudent[student1.id.uuidString]?.status == .present)
        #expect(vm.recordsByStudent[student2.id.uuidString]?.status == .present)
    }

    @Test("resetDay sets all to unmarked")
    func resetDaySetsAllToUnmarked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        // First mark them as present
        vm.load(for: date, students: [student1, student2], modelContext: context)
        vm.markAllPresent(students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudent[student1.id.uuidString]?.status == .present)
        #expect(vm.recordsByStudent[student2.id.uuidString]?.status == .present)

        // Now reset
        vm.resetDay(students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudent[student1.id.uuidString]?.status == .unmarked)
        #expect(vm.recordsByStudent[student2.id.uuidString]?.status == .unmarked)
    }

    @Test("updateNote persists note")
    func updateNotePersistsNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        vm.updateNote(for: student, note: "Doctor appointment", modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.note == "Doctor appointment")
    }

    @Test("updateNote trims whitespace")
    func updateNoteTrimsWhitespace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        vm.updateNote(for: student, note: "  Trimmed note  ", modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.note == "Trimmed note")
    }

    @Test("updateNote sets nil for empty string")
    func updateNoteSetsNilForEmptyString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        // First set a note
        vm.updateNote(for: student, note: "Some note", modelContext: context)
        #expect(vm.recordsByStudent[student.id.uuidString]?.note != nil)

        // Now clear it
        vm.updateNote(for: student, note: "   ", modelContext: context)
        #expect(vm.recordsByStudent[student.id.uuidString]?.note == nil)
    }

    @Test("updateAbsenceReason only works when absent")
    func updateAbsenceReasonOnlyWorksWhenAbsent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        // Student is unmarked, so this should not work
        vm.updateAbsenceReason(for: student, reason: .sick, modelContext: context)
        // Use AbsenceReason.none explicitly to avoid confusion with Optional.none
        #expect(vm.recordsByStudent[student.id.uuidString]?.absenceReason == AbsenceReason.none)

        // Mark as absent first
        vm.cycleStatus(for: student, modelContext: context)  // unmarked -> present
        vm.cycleStatus(for: student, modelContext: context)  // present -> absent

        // Now setting reason should work
        vm.updateAbsenceReason(for: student, reason: .sick, modelContext: context)
        #expect(vm.recordsByStudent[student.id.uuidString]?.absenceReason == .sick)
    }

    @Test("updateAbsenceReason can set vacation reason")
    func updateAbsenceReasonCanSetVacation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = AttendanceViewModel()

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .absent)
        context.insert(record)

        vm.recordsByStudent[student.id.uuidString] = record

        vm.updateAbsenceReason(for: student, reason: .vacation, modelContext: context)

        #expect(vm.recordsByStudent[student.id.uuidString]?.absenceReason == .vacation)
    }
}

// MARK: - SortKey Tests

@Suite("AttendanceViewModel.SortKey Tests", .serialized)
struct AttendanceViewModelSortKeyTests {

    @Test("SortKey has correct rawValues")
    func sortKeyRawValues() {
        #expect(AttendanceViewModel.SortKey.firstName.rawValue == "firstName")
        #expect(AttendanceViewModel.SortKey.lastName.rawValue == "lastName")
    }

    @Test("SortKey has two cases")
    func sortKeyHasTwoCases() {
        #expect(AttendanceViewModel.SortKey.allCases.count == 2)
    }

    @Test("SortKey allCases contains both values")
    func sortKeyAllCases() {
        let allCases = AttendanceViewModel.SortKey.allCases
        #expect(allCases.contains(.firstName))
        #expect(allCases.contains(.lastName))
    }
}

#endif
