#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Backup Import Compatibility Tests

@Suite("Legacy StudentLessonDTO Import")
struct BackupImportCompatibilityTests {

    /// Helper to create a StudentLessonDTO matching the old backup format
    private func makeLegacyDTO(
        id: UUID = UUID(),
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        notes: String = "",
        needsPractice: Bool = false
    ) -> StudentLessonDTO {
        StudentLessonDTO(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
            createdAt: Date(),
            scheduledFor: scheduledFor,
            givenAt: givenAt,
            isPresented: givenAt != nil,
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: false,
            followUpWork: "",
            studentGroupKey: nil
        )
    }

    @Test("Draft DTO imports as draft LessonAssignment")
    @MainActor func importDraft() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let lesson = try builder.buildLesson(name: "Test Lesson")
        let student = try builder.buildStudent(firstName: "Alice")

        let dto = makeLegacyDTO(
            lessonID: lesson.id,
            studentIDs: [student.id]
        )

        try BackupEntityImporter.importStudentLessonsAsLessonAssignments(
            [dto],
            into: context,
            existingCheck: { id in try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })).first },
            lessonCheck: { id in try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })).first },
            studentCheck: { id in try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first }
        )
        try context.save()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments.first?.state == .draft)
        #expect(assignments.first?.migratedFromStudentLessonID == dto.id.uuidString)
    }

    @Test("Scheduled DTO imports as scheduled LessonAssignment")
    @MainActor func importScheduled() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let lesson = try builder.buildLesson()
        let student = try builder.buildStudent()
        let scheduleDate = testDate(year: 2026, month: 3, day: 1)

        let dto = makeLegacyDTO(
            lessonID: lesson.id,
            studentIDs: [student.id],
            scheduledFor: scheduleDate
        )

        try BackupEntityImporter.importStudentLessonsAsLessonAssignments(
            [dto],
            into: context,
            existingCheck: { id in try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })).first },
            lessonCheck: { id in try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })).first },
            studentCheck: { id in try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first }
        )
        try context.save()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments.first?.state == .scheduled)
        #expect(assignments.first?.scheduledFor != nil)
    }

    @Test("Presented DTO imports as presented LessonAssignment")
    @MainActor func importPresented() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let lesson = try builder.buildLesson()
        let student = try builder.buildStudent()
        let givenDate = testDate(year: 2026, month: 2, day: 15)

        let dto = makeLegacyDTO(
            lessonID: lesson.id,
            studentIDs: [student.id],
            givenAt: givenDate,
            notes: "Went well"
        )

        try BackupEntityImporter.importStudentLessonsAsLessonAssignments(
            [dto],
            into: context,
            existingCheck: { id in try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })).first },
            lessonCheck: { id in try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })).first },
            studentCheck: { id in try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first }
        )
        try context.save()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments.first?.state == .presented)
        #expect(assignments.first?.presentedAt == givenDate)
        #expect(assignments.first?.notes == "Went well")
    }

    @Test("Skips DTOs with missing lesson references")
    @MainActor func skipsMissingLesson() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext

        let dto = makeLegacyDTO(
            lessonID: UUID(), // non-existent lesson
            studentIDs: [UUID()]
        )

        try BackupEntityImporter.importStudentLessonsAsLessonAssignments(
            [dto],
            into: context,
            existingCheck: { id in try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })).first },
            lessonCheck: { id in try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })).first },
            studentCheck: { id in try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first }
        )
        try context.save()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.isEmpty)
    }

    @Test("Skips duplicate imports")
    @MainActor func skipsDuplicates() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let lesson = try builder.buildLesson()
        let student = try builder.buildStudent()

        let dtoID = UUID()
        // Pre-insert a LessonAssignment with the same ID
        let existing = PresentationFactory.makeDraft(lessonID: lesson.id, studentIDs: [student.id], id: dtoID)
        context.insert(existing)
        try context.save()

        let dto = makeLegacyDTO(
            id: dtoID,
            lessonID: lesson.id,
            studentIDs: [student.id]
        )

        try BackupEntityImporter.importStudentLessonsAsLessonAssignments(
            [dto],
            into: context,
            existingCheck: { id in try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })).first },
            lessonCheck: { id in try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })).first },
            studentCheck: { id in try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first }
        )
        try context.save()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1) // Still just the original
    }

    @Test("Preserves needsPractice flag from legacy data")
    @MainActor func preservesFlags() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let lesson = try builder.buildLesson()
        let student = try builder.buildStudent()

        let dto = makeLegacyDTO(
            lessonID: lesson.id,
            studentIDs: [student.id],
            givenAt: Date(),
            needsPractice: true
        )

        try BackupEntityImporter.importStudentLessonsAsLessonAssignments(
            [dto],
            into: context,
            existingCheck: { id in try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })).first },
            lessonCheck: { id in try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })).first },
            studentCheck: { id in try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first }
        )
        try context.save()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.first?.needsPractice == true)
    }
}

#endif
