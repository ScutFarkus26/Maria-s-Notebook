#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - LessonsReorderService Basic Reorder Tests

@Suite("LessonsReorderService Basic Reorder Tests", .serialized)
@MainActor
struct LessonsReorderServiceBasicTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("reorder moves lesson from start to middle")
    func reorderFromStartToMiddle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create lessons with sequential orderInGroup
        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Group A", orderInGroup: 0)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Group A", orderInGroup: 1)
        let lesson3 = makeTestLesson(name: "Lesson 3", subject: "Math", group: "Group A", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let subset = [lesson1, lesson2, lesson3]

        // Move lesson1 from index 0 to index 2
        try LessonsReorderService.reorder(
            movingLesson: lesson1,
            fromIndex: 0,
            toIndex: 2,
            subset: subset,
            context: context
        )

        // After reorder: lesson2, lesson3, lesson1
        #expect(lesson2.orderInGroup == 0)
        #expect(lesson3.orderInGroup == 1)
        #expect(lesson1.orderInGroup == 2)
    }

    @Test("reorder moves lesson from end to start")
    func reorderFromEndToStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Group A", orderInGroup: 0)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Group A", orderInGroup: 1)
        let lesson3 = makeTestLesson(name: "Lesson 3", subject: "Math", group: "Group A", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let subset = [lesson1, lesson2, lesson3]

        // Move lesson3 from index 2 to index 0
        try LessonsReorderService.reorder(
            movingLesson: lesson3,
            fromIndex: 2,
            toIndex: 0,
            subset: subset,
            context: context
        )

        // After reorder: lesson3, lesson1, lesson2
        #expect(lesson3.orderInGroup == 0)
        #expect(lesson1.orderInGroup == 1)
        #expect(lesson2.orderInGroup == 2)
    }

    @Test("reorder handles same position (no-op)")
    func reorderSamePosition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Group A", orderInGroup: 0)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Group A", orderInGroup: 1)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let subset = [lesson1, lesson2]

        // Move lesson1 from index 0 to index 0 (no change)
        try LessonsReorderService.reorder(
            movingLesson: lesson1,
            fromIndex: 0,
            toIndex: 0,
            subset: subset,
            context: context
        )

        #expect(lesson1.orderInGroup == 0)
        #expect(lesson2.orderInGroup == 1)
    }

    @Test("reorder bounds fromIndex to valid range")
    func reorderBoundsFromIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Group A", orderInGroup: 0)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Group A", orderInGroup: 1)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let subset = [lesson1, lesson2]

        // Try with out-of-bounds fromIndex (should be bounded)
        try LessonsReorderService.reorder(
            movingLesson: lesson1,
            fromIndex: 100,
            toIndex: 0,
            subset: subset,
            context: context
        )

        // Should handle gracefully without crashing
        #expect(lesson1.orderInGroup >= 0)
        #expect(lesson2.orderInGroup >= 0)
    }

    @Test("reorder bounds toIndex to valid range")
    func reorderBoundsToIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Group A", orderInGroup: 0)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Group A", orderInGroup: 1)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let subset = [lesson1, lesson2]

        // Try with out-of-bounds toIndex (should be bounded)
        try LessonsReorderService.reorder(
            movingLesson: lesson1,
            fromIndex: 0,
            toIndex: 100,
            subset: subset,
            context: context
        )

        // Should handle gracefully without crashing
        #expect(lesson1.orderInGroup >= 0)
        #expect(lesson2.orderInGroup >= 0)
    }
}

// MARK: - LessonsReorderService Subject Reorder Tests

@Suite("LessonsReorderService Subject Reorder Tests", .serialized)
@MainActor
struct LessonsReorderServiceSubjectTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("reorderInSubject updates sortIndex for all lessons")
    func reorderInSubjectUpdatesSortIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Group A", sortIndex: 0)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Group B", sortIndex: 1)
        let lesson3 = makeTestLesson(name: "Lesson 3", subject: "Math", group: "Group A", sortIndex: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let allInSubject = [lesson1, lesson2, lesson3]

        // Move lesson1 from index 0 to index 2
        try LessonsReorderService.reorderInSubject(
            movingLesson: lesson1,
            fromIndex: 0,
            toIndex: 2,
            allLessonsInSubject: allInSubject,
            context: context
        )

        // After reorder: lesson2, lesson3, lesson1
        #expect(lesson2.sortIndex == 0)
        #expect(lesson3.sortIndex == 1)
        #expect(lesson1.sortIndex == 2)
    }

    @Test("reorderInSubject preserves lessons from different groups")
    func reorderInSubjectPreservesGroups() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonA1 = makeTestLesson(name: "A1", subject: "Math", group: "Group A", sortIndex: 0)
        let lessonB1 = makeTestLesson(name: "B1", subject: "Math", group: "Group B", sortIndex: 1)
        let lessonA2 = makeTestLesson(name: "A2", subject: "Math", group: "Group A", sortIndex: 2)
        context.insert(lessonA1)
        context.insert(lessonB1)
        context.insert(lessonA2)
        try context.save()

        let allInSubject = [lessonA1, lessonB1, lessonA2]

        try LessonsReorderService.reorderInSubject(
            movingLesson: lessonB1,
            fromIndex: 1,
            toIndex: 0,
            allLessonsInSubject: allInSubject,
            context: context
        )

        // Groups should remain unchanged
        #expect(lessonA1.group == "Group A")
        #expect(lessonB1.group == "Group B")
        #expect(lessonA2.group == "Group A")
    }
}

// MARK: - LessonsReorderService Group Reorder Tests

@Suite("LessonsReorderService Group Reorder Tests", .serialized)
@MainActor
struct LessonsReorderServiceGroupTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("reorderInGroup updates orderInGroup for all lessons")
    func reorderInGroupUpdatesOrderInGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 0)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson3 = makeTestLesson(name: "Multiplication", subject: "Math", group: "Operations", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let groupLessons = [lesson1, lesson2, lesson3]

        // Move Subtraction from index 1 to index 0
        try LessonsReorderService.reorderInGroup(
            movingLesson: lesson2,
            fromIndex: 1,
            toIndex: 0,
            groupLessons: groupLessons,
            context: context
        )

        // After reorder: Subtraction, Addition, Multiplication
        #expect(lesson2.orderInGroup == 0) // Subtraction
        #expect(lesson1.orderInGroup == 1) // Addition
        #expect(lesson3.orderInGroup == 2) // Multiplication
    }

    @Test("reorderInGroup only affects lessons in the same group")
    func reorderInGroupOnlyAffectsSameGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let operationsLesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 0)
        let geometryLesson = makeTestLesson(name: "Shapes", subject: "Math", group: "Geometry", orderInGroup: 0)
        context.insert(operationsLesson)
        context.insert(geometryLesson)
        try context.save()

        // Only reorder within Operations
        let operationsLessons = [operationsLesson]

        try LessonsReorderService.reorderInGroup(
            movingLesson: operationsLesson,
            fromIndex: 0,
            toIndex: 0,
            groupLessons: operationsLessons,
            context: context
        )

        // Geometry lesson should be unaffected
        #expect(geometryLesson.orderInGroup == 0)
        #expect(geometryLesson.group == "Geometry")
    }

    @Test("reorderInGroup handles single lesson")
    func reorderInGroupHandlesSingleLesson() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Only Lesson", subject: "Math", group: "Solo", orderInGroup: 5)
        context.insert(lesson)
        try context.save()

        let groupLessons = [lesson]

        try LessonsReorderService.reorderInGroup(
            movingLesson: lesson,
            fromIndex: 0,
            toIndex: 0,
            groupLessons: groupLessons,
            context: context
        )

        // Single lesson should get orderInGroup 0
        #expect(lesson.orderInGroup == 0)
    }
}

// MARK: - LessonsReorderService Persistence Tests

@Suite("LessonsReorderService Persistence Tests", .serialized)
@MainActor
struct LessonsReorderServicePersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("reorder persists changes to database")
    func reorderPersistsChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1ID = UUID()
        let lesson2ID = UUID()

        let lesson1 = Lesson(id: lesson1ID, name: "First", subject: "Math", group: "Group", orderInGroup: 0)
        let lesson2 = Lesson(id: lesson2ID, name: "Second", subject: "Math", group: "Group", orderInGroup: 1)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        try LessonsReorderService.reorder(
            movingLesson: lesson2,
            fromIndex: 1,
            toIndex: 0,
            subset: [lesson1, lesson2],
            context: context
        )

        // Fetch fresh from database
        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == lesson1ID || $0.id == lesson2ID },
            sortBy: [SortDescriptor(\.orderInGroup)]
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 2)
        #expect(fetched[0].name == "Second")
        #expect(fetched[1].name == "First")
    }

    @Test("reorderInSubject persists changes to database")
    func reorderInSubjectPersistsChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1ID = UUID()
        let lesson2ID = UUID()

        let lesson1 = Lesson(id: lesson1ID, name: "First", subject: "Math", group: "Group", sortIndex: 0)
        let lesson2 = Lesson(id: lesson2ID, name: "Second", subject: "Math", group: "Group", sortIndex: 1)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        try LessonsReorderService.reorderInSubject(
            movingLesson: lesson2,
            fromIndex: 1,
            toIndex: 0,
            allLessonsInSubject: [lesson1, lesson2],
            context: context
        )

        // Fetch fresh from database
        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == lesson1ID || $0.id == lesson2ID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 2)
        #expect(fetched[0].name == "Second")
        #expect(fetched[1].name == "First")
    }
}

#endif
