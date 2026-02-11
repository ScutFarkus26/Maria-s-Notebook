#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Shared Test Helpers

private enum StudentDetailTestHelpers {
    static let testTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, WorkModel.self,
        WorkParticipantEntity.self, WorkCheckIn.self, Note.self,
        GroupTrack.self, StudentTrackEnrollment.self
    ]
    
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: testTypes)
    }
}

// MARK: - StudentDetailViewModel Initialization Tests

@Suite("StudentDetailViewModel Initialization Tests", .serialized)
@MainActor
struct StudentDetailViewModelInitializationTests {

    @Test("StudentDetailViewModel initializes with student")
    func initializesWithStudent() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        #expect(vm.student.id == student.id)
        #expect(vm.student.firstName == "Alice")
    }

    @Test("StudentDetailViewModel starts with empty lessons")
    func startsWithEmptyLessons() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        #expect(vm.lessons.isEmpty)
    }

    @Test("StudentDetailViewModel starts with empty studentLessons")
    func startsWithEmptyStudentLessons() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        #expect(vm.studentLessons.isEmpty)
    }

    @Test("StudentDetailViewModel starts with empty caches")
    func startsWithEmptyCaches() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        #expect(vm.lessonsByID.isEmpty)
        #expect(vm.studentLessonsByID.isEmpty)
    }

    @Test("StudentDetailViewModel starts with nil selections")
    func startsWithNilSelections() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        #expect(vm.selectedLessonForGive == nil)
        #expect(vm.selectedStudentLessonForDetail == nil)
        #expect(vm.toastMessage == nil)
    }

    @Test("StudentDetailViewModel giveStartGiven defaults to false")
    func giveStartGivenDefaultsFalse() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        #expect(vm.giveStartGiven == false)
    }
}

// MARK: - StudentDetailViewModel WorkSummary Tests

@Suite("StudentDetailViewModel WorkSummary Tests", .serialized)
struct StudentDetailViewModelWorkSummaryTests {

    @Test("WorkSummary.empty has empty sets")
    func emptyHasEmptySets() {
        let summary = StudentDetailViewModel.WorkSummary.empty

        #expect(summary.practiceLessonIDs.isEmpty)
        #expect(summary.followUpLessonIDs.isEmpty)
        #expect(summary.pendingLessonIDs.isEmpty)
    }

    @Test("WorkSummary stores custom values")
    func storesCustomValues() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let summary = StudentDetailViewModel.WorkSummary(
            practiceLessonIDs: [id1],
            followUpLessonIDs: [id2],
            pendingLessonIDs: [id3]
        )

        #expect(summary.practiceLessonIDs.contains(id1))
        #expect(summary.followUpLessonIDs.contains(id2))
        #expect(summary.pendingLessonIDs.contains(id3))
    }
}

// MARK: - StudentDetailViewModel Data Loading Tests

@Suite("StudentDetailViewModel Data Loading Tests", .serialized)
@MainActor
struct StudentDetailViewModelDataLoadingTests {

    private func makeContainer() throws -> ModelContainer {
        return try StudentDetailTestHelpers.makeContainer()
    }

    @Test("loadData populates lessons for student")
    func loadDataPopulatesLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.lessons.count == 1)
        #expect(vm.lessons.first?.name == "Addition")
    }

    @Test("loadData populates studentLessons for student")
    func loadDataPopulatesStudentLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.studentLessons.count == 1)
        #expect(vm.studentLessons.first?.id == sl.id)
    }

    @Test("loadData only loads lessons for this student")
    func loadDataOnlyLoadsForThisStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let bob = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(alice)
        context.insert(bob)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language", group: "Reading")
        context.insert(lesson1)
        context.insert(lesson2)

        let slAlice = makeTestStudentLesson(student: alice, lesson: lesson1)
        let slBob = makeTestStudentLesson(student: bob, lesson: lesson2)
        context.insert(slAlice)
        context.insert(slBob)

        try context.save()

        let vm = StudentDetailViewModel(student: alice, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.studentLessons.count == 1)
        #expect(vm.lessons.count == 1)
        #expect(vm.lessons.first?.name == "Addition")
    }

    @Test("loadData builds lessonsByID cache")
    func loadDataBuildsLessonsByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.lessonsByID[lesson.id] != nil)
        #expect(vm.lessonsByID[lesson.id]?.name == "Addition")
    }

    @Test("loadData builds studentLessonsByID cache")
    func loadDataBuildsStudentLessonsByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.studentLessonsByID[sl.id] != nil)
    }
}

// MARK: - StudentDetailViewModel Mastered/Planned IDs Tests

@Suite("StudentDetailViewModel Mastered and Planned IDs Tests", .serialized)
@MainActor
struct StudentDetailViewModelMasteredPlannedTests {

    private func makeContainer() throws -> ModelContainer {
        return try StudentDetailTestHelpers.makeContainer()
    }

    @Test("presentedLessonIDs contains presented lessons")
    func presentedContainsPresentedLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, givenAt: Date(), isPresented: true)
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.presentedLessonIDs.contains(lesson.id))
    }

    @Test("plannedLessonIDs contains unscheduled lessons")
    func plannedContainsUnscheduledLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        sl.isPresented = false
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.plannedLessonIDs.contains(lesson.id))
    }
}

// MARK: - StudentDetailViewModel Next Lessons Tests

@Suite("StudentDetailViewModel Next Lessons Tests", .serialized)
@MainActor
struct StudentDetailViewModelNextLessonsTests {

    private func makeContainer() throws -> ModelContainer {
        return try StudentDetailTestHelpers.makeContainer()
    }

    @Test("nextLessonsForStudent contains not-yet-presented lessons")
    func nextLessonsContainsNotYetPresented() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        sl.isPresented = false
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.nextLessonsForStudent.count == 1)
        #expect(vm.nextLessonsForStudent.first?.lessonID == lesson.id)
    }

    @Test("nextLessonsForStudent excludes presented lessons")
    func nextLessonsExcludesPresented() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, givenAt: Date(), isPresented: true)
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.nextLessonsForStudent.isEmpty)
    }

    @Test("nextLessonsForStudent sorted by scheduledFor")
    func nextLessonsSortedByScheduledFor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson1 = makeTestLesson(name: "Third", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "First", subject: "Math", group: "Operations")
        let lesson3 = makeTestLesson(name: "Second", subject: "Math", group: "Operations")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)

        let date1 = TestCalendar.date(year: 2025, month: 3, day: 20)
        let date2 = TestCalendar.date(year: 2025, month: 3, day: 10)
        let date3 = TestCalendar.date(year: 2025, month: 3, day: 15)

        let sl1 = makeTestStudentLesson(student: student, lesson: lesson1, scheduledFor: date1)
        let sl2 = makeTestStudentLesson(student: student, lesson: lesson2, scheduledFor: date2)
        let sl3 = makeTestStudentLesson(student: student, lesson: lesson3, scheduledFor: date3)
        context.insert(sl1)
        context.insert(sl2)
        context.insert(sl3)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        #expect(vm.nextLessonsForStudent.count == 3)
        #expect(vm.nextLessonsForStudent[0].lessonID == lesson2.id) // First (March 10)
        #expect(vm.nextLessonsForStudent[1].lessonID == lesson3.id) // Second (March 15)
        #expect(vm.nextLessonsForStudent[2].lessonID == lesson1.id) // Third (March 20)
    }
}

// MARK: - StudentDetailViewModel Lookup Methods Tests

@Suite("StudentDetailViewModel Lookup Methods Tests", .serialized)
@MainActor
struct StudentDetailViewModelLookupMethodsTests {

    private func makeContainer() throws -> ModelContainer {
        return try StudentDetailTestHelpers.makeContainer()
    }

    @Test("latestStudentLesson returns most recent")
    func latestStudentLessonReturnsMostRecent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let date1 = TestCalendar.date(year: 2025, month: 3, day: 10)
        let date2 = TestCalendar.date(year: 2025, month: 3, day: 15)

        let sl1 = makeTestStudentLesson(student: student, lesson: lesson, givenAt: date1)
        let sl2 = makeTestStudentLesson(student: student, lesson: lesson, givenAt: date2)
        context.insert(sl1)
        context.insert(sl2)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        let latest = vm.latestStudentLesson(for: lesson.id, studentID: student.id)

        #expect(latest?.id == sl2.id)
    }

    @Test("latestStudentLesson returns nil when no matches")
    func latestStudentLessonReturnsNilWhenNoMatches() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        let unknownLessonID = UUID()
        let latest = vm.latestStudentLesson(for: unknownLessonID, studentID: student.id)

        #expect(latest == nil)
    }

    @Test("upcomingStudentLesson returns unfinished lesson")
    func upcomingStudentLessonReturnsUnfinished() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson)
        sl.givenAt = nil // Not given yet
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        let upcoming = vm.upcomingStudentLesson(for: lesson.id, studentID: student.id)

        #expect(upcoming?.id == sl.id)
    }

    @Test("upcomingStudentLesson returns nil when all given")
    func upcomingStudentLessonReturnsNilWhenAllGiven() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, givenAt: Date())
        context.insert(sl)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.loadData(modelContext: context)

        let upcoming = vm.upcomingStudentLesson(for: lesson.id, studentID: student.id)

        #expect(upcoming == nil)
    }
}

// MARK: - StudentDetailViewModel Work Methods Tests

@Suite("StudentDetailViewModel Work Methods Tests", .serialized)
@MainActor
struct StudentDetailViewModelWorkMethodsTests {

    private func makeContainer() throws -> ModelContainer {
        return try StudentDetailTestHelpers.makeContainer()
    }

    @Test("updateWorkModels sets workModelsForStudent")
    func updateWorkModelsSetsWorkModelsForStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = makeTestWorkModel(title: "Practice", workType: .practice, studentID: student.id.uuidString)
        context.insert(work)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        vm.updateWorkModels([work])

        #expect(vm.workModelsForStudent.count == 1)
        #expect(vm.workModelsForStudent.first?.title == "Practice")
    }

    @Test("fetchWorkModelsForStudent returns non-complete work")
    func fetchWorkModelsForStudentReturnsNonComplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let activeWork = makeTestWorkModel(title: "Active", workType: .practice, status: .active, studentID: student.id.uuidString)
        let completeWork = makeTestWorkModel(title: "Complete", workType: .practice, status: .complete, studentID: student.id.uuidString)
        context.insert(activeWork)
        context.insert(completeWork)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        let works = vm.fetchWorkModelsForStudent(modelContext: context)

        #expect(works.count == 1)
        #expect(works.first?.title == "Active")
    }

    @Test("fetchWork returns work by ID")
    func fetchWorkReturnsWorkByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = makeTestWorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        let fetched = vm.fetchWork(by: work.id, modelContext: context)

        #expect(fetched?.id == work.id)
        #expect(fetched?.title == "Test Work")
    }

    @Test("fetchWork returns nil for unknown ID")
    func fetchWorkReturnsNilForUnknownID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        try context.save()

        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())
        let unknownID = UUID()
        let fetched = vm.fetchWork(by: unknownID, modelContext: context)

        #expect(fetched == nil)
    }
}

// MARK: - StudentDetailViewModel Toast Tests

@Suite("StudentDetailViewModel Toast Tests", .serialized)
@MainActor
struct StudentDetailViewModelToastTests {

    @Test("showToast delegates to ToastService")
    func showToastDelegatesToToastService() throws {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let vm = StudentDetailViewModel(student: student, dependencies: try AppDependencies.makeTest())

        // Clear any existing toasts
        ToastService.shared.clearAll()

        vm.showToast("Test message")

        // showToast now delegates to the centralized ToastService
        #expect(ToastService.shared.currentToast?.message == "Test message")
    }
}

#endif
