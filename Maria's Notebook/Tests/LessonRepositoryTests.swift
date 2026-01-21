#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("LessonRepository Fetch Tests", .serialized)
@MainActor
struct LessonRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("fetchLesson returns lesson by ID")
    func fetchLessonReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        context.insert(lesson)
        try context.save()

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLesson(id: lesson.id)

        #expect(fetched != nil)
        #expect(fetched?.id == lesson.id)
        #expect(fetched?.name == "Addition")
        #expect(fetched?.subject == "Math")
    }

    @Test("fetchLesson returns nil for missing ID")
    func fetchLessonReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLesson(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchLessons returns all when no predicate")
    func fetchLessonsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math")
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language")
        let lesson3 = makeTestLesson(name: "Subtraction", subject: "Math")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLessons()

        #expect(fetched.count == 3)
    }

    @Test("fetchLessons sorts by subject, group, sortIndex by default")
    func fetchLessonsSortsBySubjectGroupIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Writing", subject: "Language", group: "Written", sortIndex: 0)
        let lesson2 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", sortIndex: 0)
        let lesson3 = makeTestLesson(name: "Reading", subject: "Language", group: "Reading", sortIndex: 0)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLessons()

        #expect(fetched[0].subject == "Language")
        #expect(fetched[1].subject == "Language")
        #expect(fetched[2].subject == "Math")
    }

    @Test("fetchLessons bySubject filters correctly")
    func fetchLessonsBySubjectFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math")
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language")
        let lesson3 = makeTestLesson(name: "Subtraction", subject: "Math")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLessons(bySubject: "Math")

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.subject == "Math" })
    }

    @Test("fetchLessons bySubject and group filters correctly")
    func fetchLessonsBySubjectAndGroupFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Fractions", subject: "Math", group: "Numbers")
        let lesson3 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLessons(bySubject: "Math", group: "Operations")

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.group == "Operations" })
    }

    @Test("fetchLessons handles empty database")
    func fetchLessonsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        let fetched = repository.fetchLessons()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("LessonRepository Create Tests", .serialized)
@MainActor
struct LessonRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("createLesson creates lesson with required fields")
    func createLessonCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        let lesson = repository.createLesson(
            name: "Addition",
            subject: "Math"
        )

        #expect(lesson.name == "Addition")
        #expect(lesson.subject == "Math")
        #expect(lesson.group == "") // Default
        #expect(lesson.sortIndex == 0) // Default
    }

    @Test("createLesson sets optional fields when provided")
    func createLessonSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        let lesson = repository.createLesson(
            name: "Long Division",
            subject: "Math",
            group: "Operations",
            subheading: "Multi-digit division",
            writeUp: "Detailed instructions for long division",
            orderInGroup: 5,
            sortIndex: 10,
            source: .personal,
            personalKind: .extension
        )

        #expect(lesson.name == "Long Division")
        #expect(lesson.group == "Operations")
        #expect(lesson.subheading == "Multi-digit division")
        #expect(lesson.writeUp == "Detailed instructions for long division")
        #expect(lesson.orderInGroup == 5)
        #expect(lesson.sortIndex == 10)
        #expect(lesson.source == .personal)
        #expect(lesson.personalKind == .extension)
    }

    @Test("createLesson persists to context")
    func createLessonPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        let lesson = repository.createLesson(
            name: "Addition",
            subject: "Math"
        )

        let fetched = repository.fetchLesson(id: lesson.id)

        #expect(fetched != nil)
        #expect(fetched?.id == lesson.id)
    }
}

// MARK: - Update Tests

@Suite("LessonRepository Update Tests", .serialized)
@MainActor
struct LessonRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("updateLesson updates name")
    func updateLessonUpdatesName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition")
        context.insert(lesson)
        try context.save()

        let repository = LessonRepository(context: context)
        let result = repository.updateLesson(id: lesson.id, name: "Addition Basics")

        #expect(result == true)
        #expect(lesson.name == "Addition Basics")
    }

    @Test("updateLesson updates subject")
    func updateLessonUpdatesSubject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(subject: "Math")
        context.insert(lesson)
        try context.save()

        let repository = LessonRepository(context: context)
        let result = repository.updateLesson(id: lesson.id, subject: "Mathematics")

        #expect(result == true)
        #expect(lesson.subject == "Mathematics")
    }

    @Test("updateLesson updates group")
    func updateLessonUpdatesGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(group: "Group A")
        context.insert(lesson)
        try context.save()

        let repository = LessonRepository(context: context)
        let result = repository.updateLesson(id: lesson.id, group: "Operations")

        #expect(result == true)
        #expect(lesson.group == "Operations")
    }

    @Test("updateLesson updates sortIndex")
    func updateLessonUpdatesSortIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(sortIndex: 0)
        context.insert(lesson)
        try context.save()

        let repository = LessonRepository(context: context)
        let result = repository.updateLesson(id: lesson.id, sortIndex: 10)

        #expect(result == true)
        #expect(lesson.sortIndex == 10)
    }

    @Test("updateLesson returns false for missing ID")
    func updateLessonReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        let result = repository.updateLesson(id: UUID(), name: "NewName")

        #expect(result == false)
    }

    @Test("updateLesson only changes specified fields")
    func updateLessonOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)
        try context.save()

        let repository = LessonRepository(context: context)
        _ = repository.updateLesson(id: lesson.id, name: "Addition Basics")

        #expect(lesson.name == "Addition Basics")
        #expect(lesson.subject == "Math") // Unchanged
        #expect(lesson.group == "Operations") // Unchanged
    }
}

// MARK: - Delete Tests

@Suite("LessonRepository Delete Tests", .serialized)
@MainActor
struct LessonRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("deleteLesson removes lesson from context")
    func deleteLessonRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson()
        context.insert(lesson)
        try context.save()

        let lessonID = lesson.id

        let repository = LessonRepository(context: context)
        try repository.deleteLesson(id: lessonID)

        let fetched = repository.fetchLesson(id: lessonID)
        #expect(fetched == nil)
    }

    @Test("deleteLesson does nothing for missing ID")
    func deleteLessonDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = LessonRepository(context: context)
        try repository.deleteLesson(id: UUID())

        // Should not throw - just silently does nothing
    }
}

#endif
