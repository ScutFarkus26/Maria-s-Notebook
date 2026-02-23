#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - StudentLesson Relationship Backfill Tests

@Suite("RelationshipBackfillService StudentLesson Tests", .serialized)
@MainActor
struct RelationshipBackfillServiceStudentLessonTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("backfillRelationshipsIfNeeded links StudentLesson to Student and Lesson")
    func backfillRelationshipsLinksEntities() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.relationships.v1")

        // Create a Student
        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)

        // Create a Lesson
        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        context.insert(lesson)

        // Create StudentLesson with only IDs set (no relationships)
        let sl = makeTestStudentLesson(lessonID: lesson.id, studentIDs: [student.id])
        context.insert(sl)
        try context.save()

        // Verify relationships are not set
        #expect(sl.lesson == nil)
        #expect(sl.students.isEmpty)

        await RelationshipBackfillService.backfillRelationshipsIfNeeded(using: context)

        // After backfill, relationships should be set
        #expect(sl.lesson?.id == lesson.id)
        #expect(sl.students.count == 1)
        #expect(sl.students[0].id == student.id)
    }

    @Test("backfillRelationshipsIfNeeded handles multiple students")
    func backfillRelationshipsHandlesMultipleStudents() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.relationships.v1")

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)

        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        context.insert(lesson)

        let sl = makeTestStudentLesson(lessonID: lesson.id, studentIDs: [student1.id, student2.id])
        context.insert(sl)
        try context.save()

        await RelationshipBackfillService.backfillRelationshipsIfNeeded(using: context)

        #expect(sl.students.count == 2)
    }

    @Test("backfillRelationshipsIfNeeded is idempotent")
    func backfillRelationshipsIsIdempotent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.relationships.v1")

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        context.insert(lesson)

        let sl = makeTestStudentLesson(lessonID: lesson.id, studentIDs: [student.id])
        context.insert(sl)
        try context.save()

        // Run twice
        await RelationshipBackfillService.backfillRelationshipsIfNeeded(using: context)
        let firstLessonID = sl.lesson?.id

        // Reset flag to force re-run
        UserDefaults.standard.removeObject(forKey: "Backfill.relationships.v1")
        await RelationshipBackfillService.backfillRelationshipsIfNeeded(using: context)
        let secondLessonID = sl.lesson?.id

        #expect(firstLessonID == secondLessonID)
    }
}

// MARK: - isPresented Backfill Tests

@Suite("RelationshipBackfillService isPresented Tests", .serialized)
@MainActor
struct RelationshipBackfillServiceIsPresentedTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("backfillIsPresentedIfNeeded sets isPresented when givenAt is set")
    func backfillIsPresentedSetsFlag() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.isPresentedFromGivenAt.v1")

        let givenDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let sl = makeTestStudentLesson(givenAt: givenDate, isPresented: false)
        context.insert(sl)
        try context.save()

        #expect(sl.isPresented == false)

        await RelationshipBackfillService.backfillIsPresentedIfNeeded(using: context)

        #expect(sl.isPresented == true)
    }

    @Test("backfillIsPresentedIfNeeded preserves false when givenAt is nil")
    func backfillIsPresentedPreservesFalse() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.isPresentedFromGivenAt.v1")

        let sl = makeTestStudentLesson(givenAt: nil, isPresented: false)
        context.insert(sl)
        try context.save()

        await RelationshipBackfillService.backfillIsPresentedIfNeeded(using: context)

        #expect(sl.isPresented == false)
    }

    @Test("backfillIsPresentedIfNeeded skips already presented")
    func backfillIsPresentedSkipsAlreadyPresented() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.isPresentedFromGivenAt.v1")

        let givenDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let sl = makeTestStudentLesson(givenAt: givenDate, isPresented: true)
        context.insert(sl)
        try context.save()

        await RelationshipBackfillService.backfillIsPresentedIfNeeded(using: context)

        // Should still be true
        #expect(sl.isPresented == true)
    }
}

// MARK: - scheduledForDay Backfill Tests

@Suite("RelationshipBackfillService scheduledForDay Tests", .serialized)
@MainActor
struct RelationshipBackfillServiceScheduledForDayTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("backfillScheduledForDayIfNeeded sets correct value from scheduledFor")
    func backfillScheduledForDaySetsCorrectValue() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.scheduledForDay.v1")

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        sl.scheduledForDay = Date.distantPast // Intentionally wrong
        context.insert(sl)
        try context.save()

        await RelationshipBackfillService.backfillScheduledForDayIfNeeded(using: context)

        let expectedDay = AppCalendar.startOfDay(scheduledDate)
        #expect(sl.scheduledForDay == expectedDay)
    }

    @Test("backfillScheduledForDayIfNeeded sets distantPast when scheduledFor is nil")
    func backfillScheduledForDaySetsDistantPast() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.scheduledForDay.v1")

        let sl = makeTestStudentLesson(scheduledFor: nil)
        sl.scheduledForDay = Date() // Intentionally wrong
        context.insert(sl)
        try context.save()

        await RelationshipBackfillService.backfillScheduledForDayIfNeeded(using: context)

        #expect(sl.scheduledForDay == Date.distantPast)
    }

    @Test("backfillScheduledForDayIfNeeded is idempotent")
    func backfillScheduledForDayIsIdempotent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Backfill.scheduledForDay.v1")

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        context.insert(sl)
        try context.save()

        await RelationshipBackfillService.backfillScheduledForDayIfNeeded(using: context)
        let firstResult = sl.scheduledForDay

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Backfill.scheduledForDay.v1")
        await RelationshipBackfillService.backfillScheduledForDayIfNeeded(using: context)
        let secondResult = sl.scheduledForDay

        #expect(firstResult == secondResult)
    }
}

// MARK: - Run All Backfills Tests

@Suite("RelationshipBackfillService Run All Tests", .serialized)
@MainActor
struct RelationshipBackfillServiceRunAllTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("runAllRelationshipBackfills completes without error")
    func runAllRelationshipBackfillsCompletes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset all flags
        UserDefaults.standard.removeObject(forKey: "Backfill.relationships.v1")
        UserDefaults.standard.removeObject(forKey: "Backfill.isPresentedFromGivenAt.v1")
        UserDefaults.standard.removeObject(forKey: "Backfill.scheduledForDay.v1")
        UserDefaults.standard.removeObject(forKey: "Backfill.presentationStudentLessonLinks.v1")
        UserDefaults.standard.removeObject(forKey: "Repair.presentationStudentLessonLinks.v2")
        UserDefaults.standard.removeObject(forKey: "Backfill.noteStudentLessonFromPresentation.v1")

        await RelationshipBackfillService.runAllRelationshipBackfills(using: context)

        // Should complete without error
    }

    @Test("runAllRelationshipBackfills is safe to run multiple times")
    func runAllRelationshipBackfillsIsSafeToRepeat() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        await RelationshipBackfillService.runAllRelationshipBackfills(using: context)
        await RelationshipBackfillService.runAllRelationshipBackfills(using: context)

        // Should complete without error
    }
}

#endif
