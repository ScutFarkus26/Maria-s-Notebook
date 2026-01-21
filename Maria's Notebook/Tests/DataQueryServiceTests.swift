#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Student Fetch Tests

@Suite("DataQueryService Student Fetch Tests", .serialized)
@MainActor
struct DataQueryServiceStudentFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("fetchAllStudents returns all students")
    func fetchAllStudentsReturnsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let service = DataQueryService(context: context)
        let students = service.fetchAllStudents()

        #expect(students.count == 2)
    }

    @Test("fetchAllStudents caches results")
    func fetchAllStudentsCachesResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)
        try context.save()

        let service = DataQueryService(context: context)

        // First fetch
        let students1 = service.fetchAllStudents()
        #expect(students1.count == 1)

        // Add another student but don't invalidate cache
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student2)
        try context.save()

        // Second fetch should return cached result (still 1)
        let students2 = service.fetchAllStudents()
        #expect(students2.count == 1)

        // After invalidation, should return updated count
        service.invalidateStudentsCache()
        let students3 = service.fetchAllStudents()
        #expect(students3.count == 2)
    }

    @Test("fetchStudents by IDs returns matching students")
    func fetchStudentsByIDsReturnsMatching() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        let service = DataQueryService(context: context)
        let ids = Set([student1.id, student3.id])
        let students = service.fetchStudents(ids: ids)

        #expect(students.count == 2)
        let fetchedNames = Set(students.map { $0.firstName })
        #expect(fetchedNames.contains("Alice"))
        #expect(fetchedNames.contains("Charlie"))
    }

    @Test("fetchStudents returns empty for empty IDs")
    func fetchStudentsReturnsEmptyForEmptyIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let service = DataQueryService(context: context)
        let students = service.fetchStudents(ids: Set<UUID>())

        #expect(students.isEmpty)
    }

    @Test("fetchStudent by ID returns correct student")
    func fetchStudentByIDReturnsCorrect() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchStudent(id: student.id)

        #expect(fetched != nil)
        #expect(fetched?.firstName == "Alice")
    }

    @Test("fetchStudent returns nil for non-existent ID")
    func fetchStudentReturnsNilForNonExistent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let service = DataQueryService(context: context)
        let fetched = service.fetchStudent(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchStudentsDictionary returns dictionary keyed by ID")
    func fetchStudentsDictionaryKeyedByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let service = DataQueryService(context: context)
        let dict = service.fetchStudentsDictionary()

        #expect(dict.count == 2)
        #expect(dict[student1.id]?.firstName == "Alice")
        #expect(dict[student2.id]?.firstName == "Bob")
    }
}

// MARK: - Lesson Fetch Tests

@Suite("DataQueryService Lesson Fetch Tests", .serialized)
@MainActor
struct DataQueryServiceLessonFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("fetchAllLessons returns all lessons")
    func fetchAllLessonsReturnsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language", group: "Literacy")
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let service = DataQueryService(context: context)
        let lessons = service.fetchAllLessons()

        #expect(lessons.count == 2)
    }

    @Test("fetchAllLessons caches results")
    func fetchAllLessonsCachesResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)
        try context.save()

        let service = DataQueryService(context: context)

        // First fetch
        let lessons1 = service.fetchAllLessons()
        #expect(lessons1.count == 1)

        // Add another lesson but don't invalidate cache
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language", group: "Literacy")
        context.insert(lesson2)
        try context.save()

        // Second fetch should return cached result
        let lessons2 = service.fetchAllLessons()
        #expect(lessons2.count == 1)

        // After invalidation
        service.invalidateLessonsCache()
        let lessons3 = service.fetchAllLessons()
        #expect(lessons3.count == 2)
    }

    @Test("fetchLessons by IDs returns matching lessons")
    func fetchLessonsByIDsReturnsMatching() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations")
        let lesson3 = makeTestLesson(name: "Reading", subject: "Language", group: "Literacy")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let service = DataQueryService(context: context)
        let ids = Set([lesson1.id, lesson3.id])
        let lessons = service.fetchLessons(ids: ids)

        #expect(lessons.count == 2)
        let fetchedNames = Set(lessons.map { $0.name })
        #expect(fetchedNames.contains("Addition"))
        #expect(fetchedNames.contains("Reading"))
    }

    @Test("fetchLesson by ID returns correct lesson")
    func fetchLessonByIDReturnsCorrect() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchLesson(id: lesson.id)

        #expect(fetched != nil)
        #expect(fetched?.name == "Addition")
    }

    @Test("fetchLessonsDictionary returns dictionary keyed by ID")
    func fetchLessonsDictionaryKeyedByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language", group: "Literacy")
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let service = DataQueryService(context: context)
        let dict = service.fetchLessonsDictionary()

        #expect(dict.count == 2)
        #expect(dict[lesson1.id]?.name == "Addition")
        #expect(dict[lesson2.id]?.name == "Reading")
    }
}

// MARK: - StudentLesson Fetch Tests

@Suite("DataQueryService StudentLesson Fetch Tests", .serialized)
@MainActor
struct DataQueryServiceStudentLessonFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("fetchPresentedStudentLessons returns presented lessons")
    func fetchPresentedStudentLessonsReturnsPresented() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let presented = makeTestStudentLesson(isPresented: true)
        let notPresented = makeTestStudentLesson(isPresented: false)
        context.insert(presented)
        context.insert(notPresented)
        try context.save()

        let service = DataQueryService(context: context)
        let lessons = service.fetchPresentedStudentLessons()

        #expect(lessons.count == 1)
        #expect(lessons[0].isPresented == true)
    }

    @Test("fetchPresentedStudentLessons includes lessons with givenAt")
    func fetchPresentedStudentLessonsIncludesGivenAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let withGivenAt = makeTestStudentLesson(givenAt: Date(), isPresented: false)
        let notPresented = makeTestStudentLesson(isPresented: false)
        context.insert(withGivenAt)
        context.insert(notPresented)
        try context.save()

        let service = DataQueryService(context: context)
        let lessons = service.fetchPresentedStudentLessons()

        #expect(lessons.count == 1)
        #expect(lessons[0].givenAt != nil)
    }

    @Test("fetchStudentLessons in date range returns matching")
    func fetchStudentLessonsInDateRangeReturnsMatching() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let inRange = makeTestStudentLesson(scheduledFor: TestCalendar.date(year: 2025, month: 1, day: 15))
        let outOfRange = makeTestStudentLesson(scheduledFor: TestCalendar.date(year: 2025, month: 2, day: 15))
        context.insert(inRange)
        context.insert(outOfRange)
        try context.save()

        let service = DataQueryService(context: context)
        let startDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let endDate = TestCalendar.date(year: 2025, month: 2, day: 1)
        let lessons = service.fetchStudentLessons(from: startDate, to: endDate)

        #expect(lessons.count == 1)
    }
}

// MARK: - WorkModel Fetch Tests

@Suite("DataQueryService WorkModel Fetch Tests", .serialized)
@MainActor
struct DataQueryServiceWorkModelFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("fetchWorkModels returns all when no status filter")
    func fetchWorkModelsReturnsAllWhenNoFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let active = makeTestWorkModel(status: .active)
        let completed = makeTestWorkModel(status: .complete)
        context.insert(active)
        context.insert(completed)
        try context.save()

        let service = DataQueryService(context: context)
        let works = service.fetchWorkModels()

        #expect(works.count == 2)
    }

    @Test("fetchWorkModels filters by status")
    func fetchWorkModelsFiltersByStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let active = makeTestWorkModel(status: .active)
        let completed = makeTestWorkModel(status: .complete)
        context.insert(active)
        context.insert(completed)
        try context.save()

        let service = DataQueryService(context: context)
        let activeWorks = service.fetchWorkModels(status: .active)

        #expect(activeWorks.count == 1)
        #expect(activeWorks[0].status == .active)
    }

    @Test("fetchOpenWorkModels returns active and review")
    func fetchOpenWorkModelsReturnsActiveAndReview() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let active = makeTestWorkModel(status: .active)
        let review = makeTestWorkModel(status: .review)
        let completed = makeTestWorkModel(status: .complete)
        context.insert(active)
        context.insert(review)
        context.insert(completed)
        try context.save()

        let service = DataQueryService(context: context)
        let openWorks = service.fetchOpenWorkModels()

        #expect(openWorks.count == 2)
        let statuses = Set(openWorks.map { $0.status })
        #expect(statuses.contains(.active))
        #expect(statuses.contains(.review))
        #expect(!statuses.contains(.complete))
    }
}

// MARK: - Cache Management Tests

@Suite("DataQueryService Cache Management Tests", .serialized)
@MainActor
struct DataQueryServiceCacheManagementTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("invalidateAllCaches clears all caches")
    func invalidateAllCachesClearsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        context.insert(student)
        context.insert(lesson)
        try context.save()

        let service = DataQueryService(context: context)

        // Populate caches
        _ = service.fetchAllStudents()
        _ = service.fetchAllLessons()

        // Add more data
        let student2 = makeTestStudent(firstName: "New")
        let lesson2 = makeTestLesson(name: "New")
        context.insert(student2)
        context.insert(lesson2)
        try context.save()

        // Verify caches don't include new data
        #expect(service.fetchAllStudents().count == 1)
        #expect(service.fetchAllLessons().count == 1)

        // Invalidate all
        service.invalidateAllCaches()

        // Now should see new data
        #expect(service.fetchAllStudents().count == 2)
        #expect(service.fetchAllLessons().count == 2)
    }

    @Test("invalidateStudentsCache only affects student caches")
    func invalidateStudentsCacheOnlyAffectsStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        context.insert(student)
        context.insert(lesson)
        try context.save()

        let service = DataQueryService(context: context)

        // Populate caches
        _ = service.fetchAllStudents()
        _ = service.fetchAllLessons()

        // Add more data
        let student2 = makeTestStudent(firstName: "New")
        let lesson2 = makeTestLesson(name: "New")
        context.insert(student2)
        context.insert(lesson2)
        try context.save()

        // Invalidate only students
        service.invalidateStudentsCache()

        // Students should reflect new data, lessons should not
        #expect(service.fetchAllStudents().count == 2)
        #expect(service.fetchAllLessons().count == 1)
    }

    @Test("invalidateLessonsCache only affects lesson caches")
    func invalidateLessonsCacheOnlyAffectsLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        context.insert(student)
        context.insert(lesson)
        try context.save()

        let service = DataQueryService(context: context)

        // Populate caches
        _ = service.fetchAllStudents()
        _ = service.fetchAllLessons()

        // Add more data
        let student2 = makeTestStudent(firstName: "New")
        let lesson2 = makeTestLesson(name: "New")
        context.insert(student2)
        context.insert(lesson2)
        try context.save()

        // Invalidate only lessons
        service.invalidateLessonsCache()

        // Lessons should reflect new data, students should not
        #expect(service.fetchAllStudents().count == 1)
        #expect(service.fetchAllLessons().count == 2)
    }
}

#endif
