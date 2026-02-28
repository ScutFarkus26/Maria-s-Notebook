#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - UnlockNextLessonService Tests

@Suite("UnlockNextLessonService")
struct UnlockNextLessonServiceTests {

    @Test("Returns noCurrentLesson when lesson ID not found")
    @MainActor func noCurrentLesson() throws {
        let result = UnlockNextLessonService.unlockNextLesson(
            after: UUID(),
            for: [UUID()],
            modelContext: try makeStandardTestContainer().mainContext,
            lessons: [],
            lessonAssignments: []
        )
        guard case .noCurrentLesson = result else {
            Issue.record("Expected .noCurrentLesson, got \(result)")
            return
        }
    }

    @Test("Returns noNextLesson when no subsequent lesson exists")
    @MainActor func noNextLesson() throws {
        let lesson = makeTestLesson(name: "Last Lesson", subject: "Math", group: "Operations", orderInGroup: 99)

        let result = UnlockNextLessonService.unlockNextLesson(
            after: lesson.id,
            for: [UUID()],
            modelContext: try makeStandardTestContainer().mainContext,
            lessons: [lesson],
            lessonAssignments: []
        )
        guard case .noNextLesson = result else {
            Issue.record("Expected .noNextLesson, got \(result)")
            return
        }
    }

    @Test("Creates a new draft when next lesson exists and no assignment present")
    @MainActor func createsNewDraft() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Ops", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Ops", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let studentID = UUID()
        let result = UnlockNextLessonService.unlockNextLesson(
            after: lesson1.id,
            for: [studentID],
            modelContext: context,
            lessons: [lesson1, lesson2],
            lessonAssignments: []
        )

        guard case .success(let created) = result else {
            Issue.record("Expected .success, got \(result)")
            return
        }
        #expect(created.lessonIDUUID == lesson2.id)
        #expect(created.manuallyUnblocked)
        #expect(created.state == .draft)
    }

    @Test("Returns alreadyUnlocked when assignment exists and is already unblocked")
    @MainActor func alreadyUnlocked() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext

        let lesson1 = makeTestLesson(name: "Lesson 1", subject: "Math", group: "Ops", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Lesson 2", subject: "Math", group: "Ops", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)

        let studentID = UUID()
        let existing = PresentationFactory.makeDraft(
            lessonID: lesson2.id,
            studentIDs: [studentID]
        )
        existing.manuallyUnblocked = true
        context.insert(existing)
        try context.save()

        let result = UnlockNextLessonService.unlockNextLesson(
            after: lesson1.id,
            for: [studentID],
            modelContext: context,
            lessons: [lesson1, lesson2],
            lessonAssignments: [existing]
        )

        guard case .alreadyUnlocked = result else {
            Issue.record("Expected .alreadyUnlocked, got \(result)")
            return
        }
    }

    @Test("getNextLessonName returns name of next lesson in sequence")
    @MainActor func getNextLessonName() throws {
        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Ops", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Ops", orderInGroup: 2)

        let name = UnlockNextLessonService.getNextLessonName(
            after: lesson1.id,
            lessons: [lesson1, lesson2]
        )
        #expect(name == "Subtraction")
    }

    @Test("getNextLessonName returns nil when no next lesson")
    @MainActor func getNextLessonNameNil() throws {
        let lesson = makeTestLesson(name: "Only Lesson", subject: "Math", group: "Ops", orderInGroup: 1)

        let name = UnlockNextLessonService.getNextLessonName(
            after: lesson.id,
            lessons: [lesson]
        )
        #expect(name == nil)
    }

    @Test("Single student convenience method works")
    @MainActor func singleStudentConvenience() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext

        let lesson1 = makeTestLesson(name: "L1", subject: "Math", group: "G", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "L2", subject: "Math", group: "G", orderInGroup: 2)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        let result = UnlockNextLessonService.unlockNextLesson(
            after: lesson1.id,
            for: UUID(),
            modelContext: context,
            lessons: [lesson1, lesson2],
            lessonAssignments: []
        )

        guard case .success = result else {
            Issue.record("Expected .success, got \(result)")
            return
        }
    }
}

#endif
