#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Helper Factory

@MainActor
private func makeStatsContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        LessonAssignment.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        Note.self,
        StudentMeeting.self,
    ])
}

private func makeTestMeeting(
    id: UUID = UUID(),
    studentID: UUID = UUID(),
    date: Date = Date()
) -> StudentMeeting {
    return StudentMeeting(
        id: id,
        studentID: studentID,
        date: date
    )
}


// MARK: - Initialization Tests

@Suite("SettingsStatsViewModel Initialization Tests", .serialized)
@MainActor
struct SettingsStatsViewModelInitializationTests {

    @Test("ViewModel initializes with zero counts")
    func initializesWithZeroCounts() {
        let vm = SettingsStatsViewModel()

        #expect(vm.studentsCount == 0)
        #expect(vm.lessonsCount == 0)
        #expect(vm.studentLessonsCount == 0)
        #expect(vm.plannedCount == 0)
        #expect(vm.givenCount == 0)
        #expect(vm.workModelsCount == 0)
        #expect(vm.presentationsCount == 0)
        #expect(vm.notesCount == 0)
        #expect(vm.meetingsCount == 0)
    }

    @Test("ViewModel initializes with isLoading false")
    func initializesWithIsLoadingFalse() {
        let vm = SettingsStatsViewModel()

        #expect(vm.isLoading == false)
    }
}

// MARK: - Student Count Tests

@Suite("SettingsStatsViewModel Student Count Tests", .serialized)
@MainActor
struct SettingsStatsViewModelStudentCountTests {

    @Test("loadCounts counts students correctly")
    func loadCountsCountsStudentsCorrectly() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        vm.loadCounts(context: context)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.studentsCount == 3)
    }

    @Test("loadCounts returns zero for no students")
    func loadCountsReturnsZeroForNoStudents() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.studentsCount == 0)
    }
}

// MARK: - Lesson Count Tests

@Suite("SettingsStatsViewModel Lesson Count Tests", .serialized)
@MainActor
struct SettingsStatsViewModelLessonCountTests {

    @Test("loadCounts counts lessons correctly")
    func loadCountsCountsLessonsCorrectly() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        let lesson1 = makeTestLesson(name: "Addition")
        let lesson2 = makeTestLesson(name: "Subtraction")
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.lessonsCount == 2)
    }
}

// MARK: - StudentLesson Count Tests

@Suite("SettingsStatsViewModel StudentLesson Count Tests", .serialized)
@MainActor
struct SettingsStatsViewModelStudentLessonCountTests {

    @Test("loadCounts counts studentLessons correctly")
    func loadCountsCountsStudentLessonsCorrectly() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        let sl1 = makeTestStudentLesson()
        let sl2 = makeTestStudentLesson()
        let sl3 = makeTestStudentLesson()
        context.insert(sl1)
        context.insert(sl2)
        context.insert(sl3)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.studentLessonsCount == 3)
    }

    @Test("loadCounts separates planned and given lessons")
    func loadCountsSeparatesPlannedAndGiven() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        // Two planned (givenAt == nil)
        let planned1 = makeTestStudentLesson(givenAt: nil)
        let planned2 = makeTestStudentLesson(givenAt: nil)

        // One given (givenAt != nil)
        let given1 = makeTestStudentLesson(givenAt: Date())

        context.insert(planned1)
        context.insert(planned2)
        context.insert(given1)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.plannedCount == 2)
        #expect(vm.givenCount == 1)
    }
}

// MARK: - WorkModel Count Tests

@Suite("SettingsStatsViewModel WorkModel Count Tests", .serialized)
@MainActor
struct SettingsStatsViewModelWorkModelCountTests {

    @Test("loadCounts counts workModels correctly")
    func loadCountsCountsWorkModelsCorrectly() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        let work1 = makeTestWorkModel(title: "Work 1")
        let work2 = makeTestWorkModel(title: "Work 2")
        context.insert(work1)
        context.insert(work2)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.workModelsCount == 2)
    }
}

// MARK: - Note Count Tests

@Suite("SettingsStatsViewModel Note Count Tests", .serialized)
@MainActor
struct SettingsStatsViewModelNoteCountTests {

    @Test("loadCounts counts notes correctly")
    func loadCountsCountsNotesCorrectly() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        let note1 = Note(body: "Note 1")
        let note2 = Note(body: "Note 2")
        context.insert(note1)
        context.insert(note2)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.notesCount == 2)
    }
}

// MARK: - Meeting Count Tests

@Suite("SettingsStatsViewModel Meeting Count Tests", .serialized)
@MainActor
struct SettingsStatsViewModelMeetingCountTests {

    @Test("loadCounts counts meetings correctly")
    func loadCountsCountsMeetingsCorrectly() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        let meeting1 = makeTestMeeting()
        let meeting2 = makeTestMeeting()
        context.insert(meeting1)
        context.insert(meeting2)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.meetingsCount == 2)
    }
}

// MARK: - Caching Tests

@Suite("SettingsStatsViewModel Caching Tests", .serialized)
@MainActor
struct SettingsStatsViewModelCachingTests {

    @Test("loadCounts uses cache within 30 seconds")
    func loadCountsUsesCacheWithin30Seconds() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        // First load
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student1)
        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.studentsCount == 1)

        // Add another student without saving
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student2)
        try context.save()

        // Second load should use cache
        vm.loadCounts(context: context)

        // Count should still be 1 due to caching
        #expect(vm.studentsCount == 1)
    }
}

// MARK: - Loading State Tests

@Suite("SettingsStatsViewModel Loading State Tests", .serialized)
@MainActor
struct SettingsStatsViewModelLoadingStateTests {

    @Test("isLoading is true during load operation")
    func isLoadingIsTrueDuringLoad() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        // Insert some data to make loading take a tiny bit longer
        for i in 0..<10 {
            context.insert(makeTestStudent(firstName: "Student \(i)", lastName: "Test"))
        }
        try context.save()

        vm.loadCounts(context: context)

        // isLoading should be true immediately after call
        #expect(vm.isLoading == true)

        // Wait for completion
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.isLoading == false)
    }
}

// MARK: - Comprehensive Count Tests

@Suite("SettingsStatsViewModel Comprehensive Tests", .serialized)
@MainActor
struct SettingsStatsViewModelComprehensiveTests {

    @Test("loadCounts populates all counts from varied data")
    func loadCountsPopulatesAllCounts() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        // Students: 3
        context.insert(makeTestStudent(firstName: "Alice", lastName: "A"))
        context.insert(makeTestStudent(firstName: "Bob", lastName: "B"))
        context.insert(makeTestStudent(firstName: "Charlie", lastName: "C"))

        // Lessons: 2
        context.insert(makeTestLesson(name: "L1"))
        context.insert(makeTestLesson(name: "L2"))

        // StudentLessons: 4 (2 planned, 2 given)
        context.insert(makeTestStudentLesson(givenAt: nil))
        context.insert(makeTestStudentLesson(givenAt: nil))
        context.insert(makeTestStudentLesson(givenAt: Date()))
        context.insert(makeTestStudentLesson(givenAt: Date()))

        // WorkModels: 2
        context.insert(makeTestWorkModel(title: "W1"))
        context.insert(makeTestWorkModel(title: "W2"))

        // Notes: 3
        context.insert(Note(body: "N1"))
        context.insert(Note(body: "N2"))
        context.insert(Note(body: "N3"))

        // Meetings: 1
        context.insert(makeTestMeeting())

        try context.save()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.studentsCount == 3)
        #expect(vm.lessonsCount == 2)
        #expect(vm.studentLessonsCount == 4)
        #expect(vm.plannedCount == 2)
        #expect(vm.givenCount == 2)
        #expect(vm.workModelsCount == 2)
        #expect(vm.notesCount == 3)
        #expect(vm.meetingsCount == 1)
    }

    @Test("loadCounts handles empty database")
    func loadCountsHandlesEmptyDatabase() async throws {
        let container = try makeStatsContainer()
        let context = ModelContext(container)
        let vm = SettingsStatsViewModel()

        vm.loadCounts(context: context)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.studentsCount == 0)
        #expect(vm.lessonsCount == 0)
        #expect(vm.studentLessonsCount == 0)
        #expect(vm.plannedCount == 0)
        #expect(vm.givenCount == 0)
        #expect(vm.workModelsCount == 0)
        #expect(vm.presentationsCount == 0)
        #expect(vm.notesCount == 0)
        #expect(vm.meetingsCount == 0)
    }
}

#endif
