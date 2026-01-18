#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Lesson Creation Tests

@Suite("Lesson Creation Tests", .serialized)
@MainActor
struct LessonCreationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("Lesson initializes with required fields")
    func initializesWithRequiredFields() {
        let lesson = Lesson(name: "Addition", subject: "Math", group: "Operations")

        #expect(lesson.name == "Addition")
        #expect(lesson.subject == "Math")
        #expect(lesson.group == "Operations")
    }

    @Test("Lesson generates unique ID")
    func generatesUniqueId() {
        let lesson1 = makeTestLesson(name: "Addition")
        let lesson2 = makeTestLesson(name: "Subtraction")

        #expect(lesson1.id != lesson2.id)
    }

    @Test("Lesson orderInGroup defaults to zero")
    func orderInGroupDefaultsToZero() {
        let lesson = Lesson(name: "Test", subject: "Math", group: "Group")

        #expect(lesson.orderInGroup == 0)
    }

    @Test("Lesson sortIndex defaults to zero")
    func sortIndexDefaultsToZero() {
        let lesson = Lesson(name: "Test", subject: "Math", group: "Group")

        #expect(lesson.sortIndex == 0)
    }

    @Test("Lesson persists to context")
    func persistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)
        try context.save()

        let descriptor = FetchDescriptor<Lesson>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Addition")
        #expect(fetched[0].subject == "Math")
        #expect(fetched[0].group == "Operations")
    }

    @Test("Lesson can have subheading")
    func canHaveSubheading() {
        let lesson = Lesson(name: "Addition", subject: "Math", group: "Operations", subheading: "Basic Facts")

        #expect(lesson.subheading == "Basic Facts")
    }

    @Test("Lesson can have writeUp")
    func canHaveWriteUp() {
        let lesson = Lesson(name: "Addition", subject: "Math", group: "Operations", writeUp: "This lesson covers...")

        #expect(lesson.writeUp == "This lesson covers...")
    }
}

// MARK: - Lesson Source Tests

@Suite("Lesson Source Tests", .serialized)
struct LessonSourceTests {

    @Test("Lesson source defaults to album")
    func sourceDefaultsToAlbum() {
        let lesson = makeTestLesson()

        #expect(lesson.source == .album)
    }

    @Test("Lesson source can be set to personal")
    func sourceCanBeSetToPersonal() {
        let lesson = makeTestLesson()
        lesson.source = .personal

        #expect(lesson.source == .personal)
    }

    @Test("LessonSource.album has correct rawValue")
    func albumHasCorrectRawValue() {
        #expect(LessonSource.album.rawValue == "album")
    }

    @Test("LessonSource.personal has correct rawValue")
    func personalHasCorrectRawValue() {
        #expect(LessonSource.personal.rawValue == "personal")
    }
}

// MARK: - Lesson Relationships Tests

@Suite("Lesson Relationships Tests", .serialized)
@MainActor
struct LessonRelationshipsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            StudentLesson.self,
            Student.self,
            Note.self,
        ])
    }

    @Test("Lesson can have multiple StudentLessons")
    func canHaveMultipleStudentLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition")
        context.insert(lesson)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let sl1 = StudentLesson(lessonID: lesson.id, studentIDs: [student1.id])
        let sl2 = StudentLesson(lessonID: lesson.id, studentIDs: [student2.id])
        sl1.lesson = lesson
        sl2.lesson = lesson
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        #expect(lesson.studentLessons?.count == 2)
    }

    @Test("Lesson can have notes")
    func canHaveNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition")
        context.insert(lesson)

        let note = Note(body: "Teaching notes for addition")
        note.lesson = lesson
        context.insert(note)
        try context.save()

        #expect(lesson.notes?.count == 1)
        #expect(lesson.notes?[0].body == "Teaching notes for addition")
    }
}

// MARK: - Lesson Ordering Tests

@Suite("Lesson Ordering Tests", .serialized)
@MainActor
struct LessonOrderingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
        ])
    }

    @Test("Lessons can be sorted by orderInGroup")
    func canBeSortedByOrderInGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Third", subject: "Math", group: "Operations", orderInGroup: 3)
        let lesson2 = makeTestLesson(name: "First", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson3 = makeTestLesson(name: "Second", subject: "Math", group: "Operations", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let descriptor = FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\.orderInGroup)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched[0].name == "First")
        #expect(fetched[1].name == "Second")
        #expect(fetched[2].name == "Third")
    }

    @Test("Lessons can be sorted by sortIndex")
    func canBeSortedBySortIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = Lesson(name: "C Lesson", subject: "Math", group: "A", sortIndex: 3)
        let lesson2 = Lesson(name: "A Lesson", subject: "Math", group: "A", sortIndex: 1)
        let lesson3 = Lesson(name: "B Lesson", subject: "Math", group: "A", sortIndex: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let descriptor = FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\.sortIndex)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched[0].name == "A Lesson")
        #expect(fetched[1].name == "B Lesson")
        #expect(fetched[2].name == "C Lesson")
    }
}

// MARK: - Lesson Persistence Tests

@Suite("Lesson Persistence Tests", .serialized)
@MainActor
struct LessonPersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            Note.self,
        ])
    }

    @Test("Lesson round-trips through persistence")
    func roundTripsThroughPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let original = Lesson(
            name: "Addition",
            subject: "Math",
            group: "Operations",
            orderInGroup: 5,
            sortIndex: 10,
            subheading: "Basic facts",
            writeUp: "Lesson content here"
        )
        let originalID = original.id

        context.insert(original)
        try context.save()

        // Fetch back (filter to avoid UUID predicate issues)
        let descriptor = FetchDescriptor<Lesson>()
        let fetched = try context.fetch(descriptor).first { $0.id == originalID }

        #expect(fetched != nil)
        #expect(fetched?.id == originalID)
        #expect(fetched?.name == "Addition")
        #expect(fetched?.subject == "Math")
        #expect(fetched?.group == "Operations")
        #expect(fetched?.orderInGroup == 5)
        #expect(fetched?.sortIndex == 10)
        #expect(fetched?.subheading == "Basic facts")
        #expect(fetched?.writeUp == "Lesson content here")
    }

    @Test("Lesson can be updated after fetch")
    func canBeUpdatedAfterFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition")
        context.insert(lesson)
        try context.save()

        // Update
        lesson.name = "Advanced Addition"
        lesson.orderInGroup = 10
        try context.save()

        // Fetch back (filter to avoid UUID predicate issues)
        let descriptor = FetchDescriptor<Lesson>()
        let fetched = try context.fetch(descriptor).first { $0.id == lesson.id }

        #expect(fetched?.name == "Advanced Addition")
        #expect(fetched?.orderInGroup == 10)
    }

    @Test("Lesson can be deleted")
    func canBeDeleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson()
        let lessonID = lesson.id
        context.insert(lesson)
        try context.save()

        context.delete(lesson)
        try context.save()

        // Fetch and filter to check deletion
        let descriptor = FetchDescriptor<Lesson>()
        let fetched = try context.fetch(descriptor).filter { $0.id == lessonID }

        #expect(fetched.isEmpty)
    }
}

// MARK: - DefaultWorkKind Tests

@Suite("Lesson DefaultWorkKind Tests", .serialized)
struct LessonDefaultWorkKindTests {

    @Test("defaultWorkKind starts nil")
    func defaultWorkKindStartsNil() {
        let lesson = makeTestLesson()

        #expect(lesson.defaultWorkKind == nil)
    }

    @Test("defaultWorkKind can be set")
    func defaultWorkKindCanBeSet() {
        let lesson = makeTestLesson()
        lesson.defaultWorkKind = .practiceLesson

        #expect(lesson.defaultWorkKind == .practiceLesson)
    }

    @Test("defaultWorkKind can be cleared")
    func defaultWorkKindCanBeCleared() {
        let lesson = makeTestLesson()
        lesson.defaultWorkKind = .followUpAssignment
        lesson.defaultWorkKind = nil

        #expect(lesson.defaultWorkKind == nil)
    }
}

#endif
