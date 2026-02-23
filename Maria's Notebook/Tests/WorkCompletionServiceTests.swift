#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - WorkCompletionService Fetching Tests

@Suite("WorkCompletionService Fetching Tests", .serialized)
@MainActor
struct WorkCompletionServiceFetchingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkCompletionRecord.self,
            Note.self,
        ])
    }

    @Test("records returns all completion records for a work")
    func recordsReturnsAllForWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let student1 = UUID()
        let student2 = UUID()

        // Create completion records
        let record1 = WorkCompletionRecord(workID: workID, studentID: student1, completedAt: Date())
        let record2 = WorkCompletionRecord(workID: workID, studentID: student2, completedAt: Date())
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let results = try WorkCompletionService.records(for: workID, in: context)

        #expect(results.count == 2)
    }

    @Test("records filters by studentID when provided")
    func recordsFiltersByStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let student1 = UUID()
        let student2 = UUID()

        let record1 = WorkCompletionRecord(workID: workID, studentID: student1, completedAt: Date())
        let record2 = WorkCompletionRecord(workID: workID, studentID: student2, completedAt: Date())
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let results = try WorkCompletionService.records(for: workID, studentID: student1, in: context)

        #expect(results.count == 1)
        #expect(results.first?.studentID == student1.uuidString)
    }

    @Test("records returns empty array when no records exist")
    func recordsReturnsEmptyWhenNone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let results = try WorkCompletionService.records(for: UUID(), in: context)

        #expect(results.isEmpty)
    }

    @Test("records returns sorted by completedAt descending")
    func recordsReturnsSortedDescending() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentID = UUID()

        let date1 = TestCalendar.date(year: 2025, month: 1, day: 1)
        let date2 = TestCalendar.date(year: 2025, month: 1, day: 15)
        let date3 = TestCalendar.date(year: 2025, month: 1, day: 10)

        let record1 = WorkCompletionRecord(workID: workID, studentID: studentID, completedAt: date1)
        let record2 = WorkCompletionRecord(workID: workID, studentID: studentID, completedAt: date2)
        let record3 = WorkCompletionRecord(workID: workID, studentID: studentID, completedAt: date3)
        context.insert(record1)
        context.insert(record2)
        context.insert(record3)
        try context.save()

        let results = try WorkCompletionService.records(for: workID, studentID: studentID, in: context)

        #expect(results.count == 3)
        // Most recent should be first
        #expect(results[0].completedAt >= results[1].completedAt)
        #expect(results[1].completedAt >= results[2].completedAt)
    }

    @Test("latest returns most recent completion record")
    func latestReturnsMostRecent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentID = UUID()

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 1, day: 15)

        let oldRecord = WorkCompletionRecord(workID: workID, studentID: studentID, completedAt: oldDate)
        let newRecord = WorkCompletionRecord(workID: workID, studentID: studentID, completedAt: newDate)
        context.insert(oldRecord)
        context.insert(newRecord)
        try context.save()

        let latest = try WorkCompletionService.latest(for: workID, studentID: studentID, in: context)

        #expect(latest != nil)
        // Latest should have the newer date
        #expect(Calendar.current.isDate(latest!.completedAt, inSameDayAs: newDate))
    }

    @Test("latest returns nil when no records exist")
    func latestReturnsNilWhenNone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let result = try WorkCompletionService.latest(for: UUID(), studentID: UUID(), in: context)

        #expect(result == nil)
    }

    @Test("isCompleted returns true when record exists")
    func isCompletedReturnsTrueWhenExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentID = UUID()

        let record = WorkCompletionRecord(workID: workID, studentID: studentID)
        context.insert(record)
        try context.save()

        let result = try WorkCompletionService.isCompleted(workID: workID, studentID: studentID, in: context)

        #expect(result == true)
    }

    @Test("isCompleted returns false when no record exists")
    func isCompletedReturnsFalseWhenNone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let result = try WorkCompletionService.isCompleted(workID: UUID(), studentID: UUID(), in: context)

        #expect(result == false)
    }

    @Test("isCompleted returns false for wrong student")
    func isCompletedReturnsFalseForWrongStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let student1 = UUID()
        let student2 = UUID()

        let record = WorkCompletionRecord(workID: workID, studentID: student1)
        context.insert(record)
        try context.save()

        let result = try WorkCompletionService.isCompleted(workID: workID, studentID: student2, in: context)

        #expect(result == false)
    }
}

// MARK: - WorkCompletionService Mutation Tests

@Suite("WorkCompletionService Mutation Tests", .serialized)
@MainActor
struct WorkCompletionServiceMutationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkCompletionRecord.self,
            Note.self,
        ])
    }

    @Test("markCompleted creates new completion record")
    func markCompletedCreatesRecord() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentID = UUID()

        let record = try WorkCompletionService.markCompleted(
            workID: workID,
            studentID: studentID,
            in: context
        )

        #expect(record.workID == workID.uuidString)
        #expect(record.studentID == studentID.uuidString)
    }

    @Test("markCompleted preserves note")
    func markCompletedPreservesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = try WorkCompletionService.markCompleted(
            workID: UUID(),
            studentID: UUID(),
            note: "Great work!",
            in: context
        )

        #expect(record.latestUnifiedNoteText == "Great work!")
    }

    @Test("markCompleted uses provided date")
    func markCompletedUsesDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let specificDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let record = try WorkCompletionService.markCompleted(
            workID: UUID(),
            studentID: UUID(),
            at: specificDate,
            in: context
        )

        #expect(Calendar.current.isDate(record.completedAt, inSameDayAs: specificDate))
    }

    @Test("markCompleted persists to database")
    func markCompletedPersists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentID = UUID()

        _ = try WorkCompletionService.markCompleted(
            workID: workID,
            studentID: studentID,
            in: context
        )

        // Verify it was persisted
        let isCompleted = try WorkCompletionService.isCompleted(workID: workID, studentID: studentID, in: context)
        #expect(isCompleted == true)
    }

    @Test("markCompleted with work and student instances")
    func markCompletedWithInstances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(work)
        context.insert(student)
        try context.save()

        let record = try WorkCompletionService.markCompleted(
            work: work,
            student: student,
            note: "Completed via instance method",
            in: context
        )

        #expect(record.workID == work.id.uuidString)
        #expect(record.studentID == student.id.uuidString)
        #expect(record.latestUnifiedNoteText == "Completed via instance method")
    }

    @Test("markCompleted allows multiple completions for history")
    func markCompletedAllowsMultiple() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentID = UUID()

        let date1 = TestCalendar.date(year: 2025, month: 1, day: 1)
        let date2 = TestCalendar.date(year: 2025, month: 1, day: 15)

        _ = try WorkCompletionService.markCompleted(
            workID: workID,
            studentID: studentID,
            note: "First completion",
            at: date1,
            in: context
        )

        _ = try WorkCompletionService.markCompleted(
            workID: workID,
            studentID: studentID,
            note: "Second completion",
            at: date2,
            in: context
        )

        let records = try WorkCompletionService.records(for: workID, studentID: studentID, in: context)

        #expect(records.count == 2)
    }
}

// MARK: - WorkCompletionService Integration Tests

@Suite("WorkCompletionService Integration Tests", .serialized)
@MainActor
struct WorkCompletionServiceIntegrationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkCompletionRecord.self,
            Note.self,
        ])
    }

    @Test("Full completion workflow")
    func fullCompletionWorkflow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Setup: Create work and students
        let work = WorkModel(title: "Practice Addition", kind: .practiceLesson)
        let student1 = makeTestStudent(firstName: "Alice", lastName: "A")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "B")
        context.insert(work)
        context.insert(student1)
        context.insert(student2)
        try context.save()

        // Verify neither student has completed
        #expect(try WorkCompletionService.isCompleted(workID: work.id, studentID: student1.id, in: context) == false)
        #expect(try WorkCompletionService.isCompleted(workID: work.id, studentID: student2.id, in: context) == false)

        // Student 1 completes
        _ = try WorkCompletionService.markCompleted(
            work: work,
            student: student1,
            note: "Alice finished!",
            in: context
        )

        // Verify only student 1 is marked complete
        #expect(try WorkCompletionService.isCompleted(workID: work.id, studentID: student1.id, in: context) == true)
        #expect(try WorkCompletionService.isCompleted(workID: work.id, studentID: student2.id, in: context) == false)

        // Student 2 completes
        _ = try WorkCompletionService.markCompleted(
            work: work,
            student: student2,
            note: "Bob finished!",
            in: context
        )

        // Verify both are complete
        #expect(try WorkCompletionService.isCompleted(workID: work.id, studentID: student1.id, in: context) == true)
        #expect(try WorkCompletionService.isCompleted(workID: work.id, studentID: student2.id, in: context) == true)

        // Get all records for the work
        let allRecords = try WorkCompletionService.records(for: work.id, in: context)
        #expect(allRecords.count == 2)
    }

    @Test("Completion history preservation")
    func completionHistoryPreservation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Repeated Practice", kind: .practiceLesson)
        let student = makeTestStudent()
        context.insert(work)
        context.insert(student)
        try context.save()

        // Complete the work multiple times (simulating re-doing practice)
        let dates = [
            TestCalendar.date(year: 2025, month: 1, day: 1),
            TestCalendar.date(year: 2025, month: 2, day: 1),
            TestCalendar.date(year: 2025, month: 3, day: 1),
        ]

        for (index, date) in dates.enumerated() {
            _ = try WorkCompletionService.markCompleted(
                work: work,
                student: student,
                note: "Completion \(index + 1)",
                at: date,
                in: context
            )
        }

        // Verify all completions are preserved
        let records = try WorkCompletionService.records(for: work.id, studentID: student.id, in: context)
        #expect(records.count == 3)

        // Latest should be the most recent
        let latest = try WorkCompletionService.latest(for: work.id, studentID: student.id, in: context)
        #expect(latest?.note == "Completion 3")
    }
}

#endif
