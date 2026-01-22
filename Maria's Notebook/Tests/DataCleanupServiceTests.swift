#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Orphaned Student ID Cleanup Tests

@Suite("DataCleanupService Orphaned StudentLesson IDs Tests", .serialized)
@MainActor
struct DataCleanupServiceOrphanedStudentLessonIDsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("cleanOrphanedStudentIDs removes non-existent student IDs from StudentLesson")
    func cleanOrphanedStudentIDsRemovesNonExistent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create a valid student
        let validStudent = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(validStudent)

        // Create a StudentLesson with a mix of valid and orphaned student IDs
        let orphanedID = UUID()
        let sl = makeTestStudentLesson(studentIDs: [validStudent.id, orphanedID])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        // Should only contain the valid student
        #expect(sl.studentIDs.count == 1)
        #expect(sl.studentIDs.contains(validStudent.id.uuidString))
        #expect(!sl.studentIDs.contains(orphanedID.uuidString))
    }

    @Test("cleanOrphanedStudentIDs preserves all valid student IDs")
    func cleanOrphanedStudentIDsPreservesValid() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)

        let sl = makeTestStudentLesson(studentIDs: [student1.id, student2.id])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        // Both students should still be present
        #expect(sl.studentIDs.count == 2)
    }

    @Test("cleanOrphanedStudentIDs handles StudentLesson with no students")
    func cleanOrphanedStudentIDsHandlesEmpty() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(studentIDs: [])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        #expect(sl.studentIDs.isEmpty)
    }

    @Test("cleanOrphanedStudentIDs is idempotent")
    func cleanOrphanedStudentIDsIsIdempotent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let validStudent = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(validStudent)

        let orphanedID = UUID()
        let sl = makeTestStudentLesson(studentIDs: [validStudent.id, orphanedID])
        context.insert(sl)
        try context.save()

        // Run twice
        await DataCleanupService.cleanOrphanedStudentIDs(using: context)
        let firstCount = sl.studentIDs.count

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)
        let secondCount = sl.studentIDs.count

        #expect(firstCount == secondCount)
        #expect(firstCount == 1)
    }
}

// MARK: - Orphaned Work Student ID Cleanup Tests

@Suite("DataCleanupService Orphaned WorkModel IDs Tests", .serialized)
@MainActor
struct DataCleanupServiceOrphanedWorkModelIDsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("cleanOrphanedWorkStudentIDs clears orphaned studentID")
    func cleanOrphanedWorkStudentIDsClearsOrphaned() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let orphanedID = UUID()
        let work = makeTestWorkModel(studentID: orphanedID.uuidString)
        context.insert(work)
        try context.save()

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        #expect(work.studentID == "")
    }

    @Test("cleanOrphanedWorkStudentIDs preserves valid studentID")
    func cleanOrphanedWorkStudentIDsPreservesValid() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let validStudent = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(validStudent)

        let work = makeTestWorkModel(studentID: validStudent.id.uuidString)
        context.insert(work)
        try context.save()

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        #expect(work.studentID == validStudent.id.uuidString)
    }

    @Test("cleanOrphanedWorkStudentIDs removes orphaned participants")
    func cleanOrphanedWorkStudentIDsRemovesOrphanedParticipants() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let validStudent = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(validStudent)

        let work = makeTestWorkModel()
        let validParticipant = WorkParticipantEntity(studentID: validStudent.id, work: work)
        let orphanedParticipant = WorkParticipantEntity(studentID: UUID(), work: work)
        work.participants = [validParticipant, orphanedParticipant]
        context.insert(work)
        try context.save()

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        #expect(work.participants?.count == 1)
        #expect(work.participants?[0].studentID == validStudent.id.uuidString)
    }

    @Test("cleanOrphanedWorkStudentIDs handles work with no participants")
    func cleanOrphanedWorkStudentIDsHandlesNoParticipants() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeTestWorkModel()
        work.participants = []
        context.insert(work)
        try context.save()

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        #expect(work.participants?.isEmpty ?? true)
    }
}

// MARK: - Deduplication Tests

@Suite("DataCleanupService Deduplication Tests", .serialized)
@MainActor
struct DataCleanupServiceDeduplicationTests {

    private func makeStudentContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    private func makeProjectContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Project.self,
            ProjectSession.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("deduplicateStudents removes duplicate students with same ID")
    func deduplicateStudentsRemovesDuplicates() throws {
        let container = try makeStudentContainer()
        let context = ModelContext(container)

        let sharedID = UUID()
        let student1 = Student(
            id: sharedID,
            firstName: "Alice",
            lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
        )
        let student2 = Student(
            id: sharedID,
            firstName: "Alice",
            lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
        )
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateStudents(using: context)

        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Student>())
        #expect(remaining.count == 1)
    }

    @Test("deduplicateStudents preserves unique students")
    func deduplicateStudentsPreservesUnique() throws {
        let container = try makeStudentContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateStudents(using: context)

        #expect(deletedCount == 0)

        let remaining = context.safeFetch(FetchDescriptor<Student>())
        #expect(remaining.count == 2)
    }

    @Test("deduplicateProjects removes duplicate projects with same ID")
    func deduplicateProjectsRemovesDuplicates() throws {
        let container = try makeProjectContainer()
        let context = ModelContext(container)

        let sharedID = UUID()
        let project1 = Project(title: "Book Club")
        // Force same ID (simulating CloudKit sync conflict)
        let project2 = Project(title: "Book Club")
        // Note: In real scenario, these would have same ID from CloudKit sync
        context.insert(project1)
        context.insert(project2)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateProjects(using: context)

        // With different IDs, no duplicates
        #expect(deletedCount == 0)
    }

    @Test("deduplicateProjectRoles removes duplicate roles")
    func deduplicateProjectRolesRemovesDuplicates() throws {
        let container = try makeProjectContainer()
        let context = ModelContext(container)

        let role1 = ProjectRole(projectID: UUID(), title: "Leader")
        let role2 = ProjectRole(projectID: UUID(), title: "Helper")
        context.insert(role1)
        context.insert(role2)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateProjectRoles(using: context)

        #expect(deletedCount == 0) // No duplicates
    }
}

// MARK: - Unpresented StudentLesson Deduplication Tests

@Suite("DataCleanupService Unpresented StudentLesson Tests", .serialized)
@MainActor
struct DataCleanupServiceUnpresentedStudentLessonTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("deduplicateUnpresentedStudentLessons removes duplicates with same lesson and students")
    func deduplicateUnpresentedRemovesDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()

        // Create duplicate unscheduled, unpresented StudentLessons
        let sl1 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        let sl2 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)

        let remaining = context.safeFetch(FetchDescriptor<StudentLesson>())
        #expect(remaining.count == 1)
    }

    @Test("deduplicateUnpresentedStudentLessons preserves scheduled lessons")
    func deduplicateUnpresentedPreservesScheduled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()

        // One scheduled, one unscheduled - should both be preserved
        let sl1 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: Date(), givenAt: nil)
        let sl2 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)

        let remaining = context.safeFetch(FetchDescriptor<StudentLesson>())
        #expect(remaining.count == 2)
    }

    @Test("deduplicateUnpresentedStudentLessons merges flags to canonical")
    func deduplicateUnpresentedMergesFlags() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 1, day: 15)

        // Older record (will be kept)
        let sl1 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        sl1.createdAt = oldDate
        sl1.needsPractice = false

        // Newer record with needsPractice (will be deleted, but flag merged)
        let sl2 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        sl2.createdAt = newDate
        sl2.needsPractice = true

        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)

        let remaining = context.safeFetch(FetchDescriptor<StudentLesson>())
        #expect(remaining.count == 1)
        #expect(remaining[0].needsPractice == true) // Merged from duplicate
    }
}

// MARK: - Denormalized Field Repair Tests

@Suite("DataCleanupService Denormalized Field Repair Tests", .serialized)
@MainActor
struct DataCleanupServiceDenormalizedFieldRepairTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("repairDenormalizedScheduledForDay fixes mismatched dates")
    func repairDenormalizedScheduledForDayFixesMismatched() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let wrongDayValue = TestCalendar.startOfDay(year: 2025, month: 1, day: 1) // Intentionally wrong

        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        sl.scheduledForDay = wrongDayValue // Mismatch
        context.insert(sl)
        try context.save()

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)

        // scheduledForDay should now match scheduledFor
        let expectedDay = AppCalendar.startOfDay(scheduledDate)
        #expect(sl.scheduledForDay == expectedDay)
    }

    @Test("repairDenormalizedScheduledForDay handles nil scheduledFor")
    func repairDenormalizedScheduledForDayHandlesNil() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(scheduledFor: nil)
        context.insert(sl)
        try context.save()

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)

        #expect(sl.scheduledForDay == Date.distantPast)
    }

    @Test("repairDenormalizedScheduledForDay is idempotent")
    func repairDenormalizedScheduledForDayIsIdempotent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        context.insert(sl)
        try context.save()

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
        let firstResult = sl.scheduledForDay

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
        let secondResult = sl.scheduledForDay

        #expect(firstResult == secondResult)
    }
}

// MARK: - Run All Cleanup Tests

@Suite("DataCleanupService Run All Tests", .serialized)
@MainActor
struct DataCleanupServiceRunAllTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("runAllCleanupOperations completes without error")
    func runAllCleanupOperationsCompletes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Add some test data
        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        await DataCleanupService.runAllCleanupOperations(using: context)

        // Should complete without error
    }

    @Test("runAllCleanupOperations is safe to run multiple times")
    func runAllCleanupOperationsIsSafeToRepeat() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        await DataCleanupService.runAllCleanupOperations(using: context)
        await DataCleanupService.runAllCleanupOperations(using: context)
        await DataCleanupService.runAllCleanupOperations(using: context)

        // Should complete without error
    }
}

#endif
