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

        #expect(vm.recordsByStudentID.isEmpty)
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
        TestPatterns.expectEmpty(sorted)
    }

    @Test("sortedAndFiltered handles single element")
    func handlesSingleElement() {
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Solo", lastName: "Student")
        let sorted = vm.sortedAndFiltered(students: [student])

        TestPatterns.expectCount(sorted, equals: 1)
        #expect(sorted[0].firstName == "Solo")
    }
}

// MARK: - Status Cycling Tests

@Suite("AttendanceViewModel Status Cycling Tests", .serialized)
@MainActor
struct AttendanceViewModelStatusCyclingTests {

    private static let models: [any PersistentModel.Type] = [Student.self, AttendanceRecord.self, Note.self]

    @Test("cycleStatus transitions unmarked to present")
    func cyclesUnmarkedToPresent() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        StatusCycleTester.testStatusCycle(from: .unmarked, to: .present, using: vm, student: student, context: context)
    }

    @Test("cycleStatus transitions present to absent")
    func cyclesPresentToAbsent() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        StatusCycleTester.testStatusCycle(from: .present, to: .absent, using: vm, student: student, context: context)
    }

    @Test("cycleStatus transitions absent to tardy")
    func cyclesAbsentToTardy() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        StatusCycleTester.testStatusCycle(from: .absent, to: .tardy, using: vm, student: student, context: context)
    }

    @Test("cycleStatus transitions tardy to leftEarly")
    func cyclesTardyToLeftEarly() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        StatusCycleTester.testStatusCycle(from: .tardy, to: .leftEarly, using: vm, student: student, context: context)
    }

    @Test("cycleStatus transitions leftEarly to present")
    func cyclesLeftEarlyToPresent() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        StatusCycleTester.testStatusCycle(from: .leftEarly, to: .present, using: vm, student: student, context: context)
    }

    @Test("cycleStatus does nothing for unknown student")
    func doesNothingForUnknownStudent() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Unknown", lastName: "Student")

        vm.cycleStatus(for: student, modelContext: context)

        #expect(vm.recordsByStudentID[student.cloudKitKey] == nil)
    }
}

// MARK: - Loading Tests

@Suite("AttendanceViewModel Loading Tests", .serialized)
@MainActor
struct AttendanceViewModelLoadingTests {

    private static let models: [any PersistentModel.Type] = [Student.self, AttendanceRecord.self, Note.self]

    @Test("load populates recordsByStudent")
    func loadPopulatesRecords() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student1, student2], modelContext: context)

        TestPatterns.expectCount(vm.recordsByStudentID, equals: 2)
        #expect(vm.recordsByStudentID[student1.cloudKitKey] != nil)
        #expect(vm.recordsByStudentID[student2.cloudKitKey] != nil)
    }

    @Test("load filters to provided students only")
    func loadFiltersToProvidedStudents() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        let extraRecord = makeTestAttendanceRecord(studentID: student3.id, date: date)
        context.insert(extraRecord)

        vm.load(for: date, students: [student1, student2], modelContext: context)

        TestPatterns.expectCount(vm.recordsByStudentID, equals: 2)
        #expect(vm.recordsByStudentID[student3.cloudKitKey] == nil)
    }

    @Test("load handles empty student list")
    func loadHandlesEmptyStudentList() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [], modelContext: context)

        TestPatterns.expectEmpty(vm.recordsByStudentID)
    }

    @Test("load updates selectedDate")
    func loadUpdatesSelectedDate() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
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
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "New", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        #expect(vm.recordsByStudentID[student.cloudKitKey]?.status == .unmarked)
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

        vm.recordsByStudentID[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .present)
        vm.recordsByStudentID[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)
        vm.recordsByStudentID[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .absent)

        #expect(vm.countPresent == 2)
    }

    @Test("countAbsent returns correct count")
    func countAbsentReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.recordsByStudentID[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .absent)
        vm.recordsByStudentID[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)
        vm.recordsByStudentID[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .absent)

        #expect(vm.countAbsent == 2)
    }

    @Test("countTardy returns correct count")
    func countTardyReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()

        vm.recordsByStudentID[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .tardy)
        vm.recordsByStudentID[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)

        #expect(vm.countTardy == 1)
    }

    @Test("countLeftEarly returns correct count")
    func countLeftEarlyReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.recordsByStudentID[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .leftEarly)
        vm.recordsByStudentID[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .leftEarly)
        vm.recordsByStudentID[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .leftEarly)

        #expect(vm.countLeftEarly == 3)
    }

    @Test("countUnmarked returns correct count")
    func countUnmarkedReturnsCorrectCount() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()

        vm.recordsByStudentID[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .unmarked)
        vm.recordsByStudentID[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)

        #expect(vm.countUnmarked == 1)
    }

    @Test("inClassCount sums present and tardy")
    func inClassCountSumsPresentAndTardy() {
        let vm = AttendanceViewModel()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()

        vm.recordsByStudentID[id1.uuidString] = makeTestAttendanceRecord(studentID: id1, status: .present)
        vm.recordsByStudentID[id2.uuidString] = makeTestAttendanceRecord(studentID: id2, status: .present)
        vm.recordsByStudentID[id3.uuidString] = makeTestAttendanceRecord(studentID: id3, status: .tardy)
        vm.recordsByStudentID[id4.uuidString] = makeTestAttendanceRecord(studentID: id4, status: .absent)

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

    private static let models: [any PersistentModel.Type] = [Student.self, AttendanceRecord.self, Note.self]

    @Test("markAllPresent updates all records to present")
    func markAllPresentUpdatesAllRecords() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudentID[student1.cloudKitKey]?.status == .unmarked)
        #expect(vm.recordsByStudentID[student2.cloudKitKey]?.status == .unmarked)

        vm.markAllPresent(students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudentID[student1.cloudKitKey]?.status == .present)
        #expect(vm.recordsByStudentID[student2.cloudKitKey]?.status == .present)
    }

    @Test("resetDay sets all to unmarked")
    func resetDaySetsAllToUnmarked() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)

        vm.load(for: date, students: [student1, student2], modelContext: context)
        vm.markAllPresent(students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudentID[student1.cloudKitKey]?.status == .present)
        #expect(vm.recordsByStudentID[student2.cloudKitKey]?.status == .present)

        vm.resetDay(students: [student1, student2], modelContext: context)

        #expect(vm.recordsByStudentID[student1.cloudKitKey]?.status == .unmarked)
        #expect(vm.recordsByStudentID[student2.cloudKitKey]?.status == .unmarked)
    }

    @Test("updateNote persists note")
    func updateNotePersistsNote() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        vm.updateNote(for: student, note: "Doctor appointment", modelContext: context)

        #expect(vm.recordsByStudentID[student.cloudKitKey]?.latestUnifiedNoteText == "Doctor appointment")
    }

    @Test("updateNote trims whitespace")
    func updateNoteTrimsWhitespace() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        vm.updateNote(for: student, note: "  Trimmed note  ", modelContext: context)

        #expect(vm.recordsByStudentID[student.cloudKitKey]?.latestUnifiedNoteText == "Trimmed note")
    }

    @Test("updateNote sets nil for empty string")
    func updateNoteSetsNilForEmptyString() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        vm.updateNote(for: student, note: "Some note", modelContext: context)
        #expect(!vm.recordsByStudentID[student.cloudKitKey]!.latestUnifiedNoteText.isEmpty)

        vm.updateNote(for: student, note: "   ", modelContext: context)
        #expect(vm.recordsByStudentID[student.cloudKitKey]!.latestUnifiedNoteText.isEmpty)
    }

    @Test("updateAbsenceReason only works when absent")
    func updateAbsenceReasonOnlyWorksWhenAbsent() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let date = TestCalendar.date(year: 2025, month: 1, day: 15)
        vm.load(for: date, students: [student], modelContext: context)

        vm.updateAbsenceReason(for: student, reason: .sick, modelContext: context)
        #expect(vm.recordsByStudentID[student.cloudKitKey]?.absenceReason == AbsenceReason.none)

        vm.cycleStatus(for: student, modelContext: context)
        vm.cycleStatus(for: student, modelContext: context)

        vm.updateAbsenceReason(for: student, reason: .sick, modelContext: context)
        #expect(vm.recordsByStudentID[student.cloudKitKey]?.absenceReason == .sick)
    }

    @Test("updateAbsenceReason can set vacation reason")
    func updateAbsenceReasonCanSetVacation() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let vm = AttendanceViewModel()
        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        context.insert(student)

        let record = makeTestAttendanceRecord(studentID: student.id, status: .absent)
        context.insert(record)

        vm.recordsByStudentID[student.cloudKitKey] = record

        vm.updateAbsenceReason(for: student, reason: .vacation, modelContext: context)

        #expect(vm.recordsByStudentID[student.cloudKitKey]?.absenceReason == .vacation)
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
