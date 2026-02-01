#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - LessonAssignment Migration Tests

@Suite("LessonAssignmentMigrationService Tests", .serialized)
@MainActor
struct LessonAssignmentMigrationServiceTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Presentation.self,
            LessonAssignment.self,
            LessonPresentation.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    // MARK: - Basic Migration Tests

    @Test("Migrates draft StudentLesson to draft LessonAssignment")
    func migratesDraftStudentLesson() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        // Create a draft StudentLesson (unscheduled, not presented)
        let lessonID = UUID()
        let studentIDs = [UUID(), UUID()]
        let sl = StudentLesson(
            id: UUID(),
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false
        )
        context.insert(sl)
        try context.save()

        // Run migration
        let service = LessonAssignmentMigrationService(context: context)
        let result = try await service.migrateAll()

        #expect(result.studentLessonsMigrated == 1)
        #expect(result.studentLessonsSkipped == 0)

        // Verify LessonAssignment was created
        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)

        let la = assignments[0]
        #expect(la.state == .draft)
        #expect(la.lessonID == lessonID.uuidString)
        #expect(la.studentIDs.count == 2)
        #expect(la.scheduledFor == nil)
        #expect(la.presentedAt == nil)
        #expect(la.migratedFromStudentLessonID == sl.id.uuidString)
    }

    @Test("Migrates scheduled StudentLesson to scheduled LessonAssignment")
    func migratesScheduledStudentLesson() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        let scheduledDate = Date()
        let sl = StudentLesson(
            id: UUID(),
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: scheduledDate,
            givenAt: nil,
            isPresented: false
        )
        context.insert(sl)
        try context.save()

        let service = LessonAssignmentMigrationService(context: context)
        _ = try await service.migrateAll()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments[0].state == .scheduled)
        #expect(assignments[0].scheduledFor != nil)
    }

    @Test("Migrates presented StudentLesson to presented LessonAssignment")
    func migratesPresentedStudentLesson() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        let givenDate = Date()
        let sl = StudentLesson(
            id: UUID(),
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: nil,
            givenAt: givenDate,
            isPresented: true
        )
        context.insert(sl)
        try context.save()

        let service = LessonAssignmentMigrationService(context: context)
        _ = try await service.migrateAll()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments[0].state == .presented)
        #expect(assignments[0].presentedAt != nil)
    }

    @Test("Links Presentation data to migrated LessonAssignment")
    func linksPresentationData() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        // Create StudentLesson
        let slID = UUID()
        let lessonID = UUID()
        let sl = StudentLesson(
            id: slID,
            lessonID: lessonID,
            studentIDs: [UUID()],
            scheduledFor: nil,
            givenAt: Date(),
            isPresented: true
        )
        context.insert(sl)

        // Create linked Presentation
        let presentation = Presentation(
            presentedAt: Date(),
            lessonID: lessonID.uuidString,
            studentIDs: [UUID().uuidString],
            legacyStudentLessonID: slID.uuidString,
            trackID: "track-123",
            trackStepID: "step-456",
            lessonTitleSnapshot: "Test Lesson",
            lessonSubtitleSnapshot: "Subheading"
        )
        context.insert(presentation)
        try context.save()

        let service = LessonAssignmentMigrationService(context: context)
        _ = try await service.migrateAll()

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)

        let la = assignments[0]
        #expect(la.trackID == "track-123")
        #expect(la.trackStepID == "step-456")
        #expect(la.lessonTitleSnapshot == "Test Lesson")
        #expect(la.lessonSubheadingSnapshot == "Subheading")
        #expect(la.migratedFromPresentationID == presentation.id.uuidString)
    }

    @Test("Migration is idempotent - running twice doesn't duplicate")
    func migrationIsIdempotent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        let sl = StudentLesson(
            id: UUID(),
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false
        )
        context.insert(sl)
        try context.save()

        let service = LessonAssignmentMigrationService(context: context)

        // Run migration twice
        let result1 = try await service.migrateAll()
        let result2 = try await service.migrateAll()

        #expect(result1.studentLessonsMigrated == 1)
        #expect(result2.studentLessonsMigrated == 0) // Should skip on second run
        #expect(result2.studentLessonsSkipped == 1)

        // Should still only have one LessonAssignment
        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
    }

    @Test("Migrates orphaned Presentation without linked StudentLesson")
    func migratesOrphanedPresentation() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        // Create a Presentation without a linked StudentLesson
        let presentation = Presentation(
            presentedAt: Date(),
            lessonID: UUID().uuidString,
            studentIDs: [UUID().uuidString],
            legacyStudentLessonID: nil, // No linked StudentLesson
            lessonTitleSnapshot: "Orphan Lesson"
        )
        context.insert(presentation)
        try context.save()

        let service = LessonAssignmentMigrationService(context: context)
        let result = try await service.migrateAll()

        #expect(result.presentationsMigrated == 1)

        let assignments = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments[0].state == .presented)
        #expect(assignments[0].lessonTitleSnapshot == "Orphan Lesson")
        #expect(assignments[0].migratedFromPresentationID == presentation.id.uuidString)
    }

    // MARK: - Validation Tests

    @Test("Validator passes when all records migrated")
    func validatorPassesWhenComplete() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        MigrationFlag.reset(key: "Migration.lessonAssignment.v1")

        // Create and migrate a StudentLesson
        let sl = StudentLesson(
            id: UUID(),
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false
        )
        context.insert(sl)
        try context.save()

        let service = LessonAssignmentMigrationService(context: context)
        _ = try await service.migrateAll()

        // Validate
        let validator = LessonAssignmentMigrationValidator(context: context)
        let result = try await validator.validate()

        #expect(result.isValid)
        #expect(result.unmatchedStudentLessons.isEmpty)
        #expect(result.unmatchedPresentations.isEmpty)
    }

    @Test("Validator detects unmatched StudentLesson")
    func validatorDetectsUnmatchedStudentLesson() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create a StudentLesson but don't migrate it
        let sl = StudentLesson(
            id: UUID(),
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false
        )
        context.insert(sl)
        try context.save()

        // Validate without migrating
        let validator = LessonAssignmentMigrationValidator(context: context)
        let result = try await validator.validate()

        #expect(!result.isValid)
        #expect(result.unmatchedStudentLessons.count == 1)
        #expect(result.unmatchedStudentLessons[0].id == sl.id)
    }
}

// MARK: - LessonAssignment Model Tests

@Suite("LessonAssignment Model Tests")
@MainActor
struct LessonAssignmentModelTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            LessonAssignment.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("State transitions work correctly")
    func stateTransitionsWork() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let la = LessonAssignment(
            lessonID: UUID(),
            studentIDs: [UUID()]
        )
        context.insert(la)

        // Initial state is draft
        #expect(la.state == .draft)
        #expect(la.isDraft)
        #expect(!la.isScheduled)
        #expect(!la.isPresented)

        // Schedule
        let scheduledDate = Date()
        la.schedule(for: scheduledDate)
        #expect(la.state == .scheduled)
        #expect(la.isScheduled)
        #expect(la.scheduledFor != nil)

        // Unschedule back to draft
        la.unschedule()
        #expect(la.state == .draft)
        #expect(la.scheduledFor == nil)

        // Mark presented
        la.markPresented()
        #expect(la.state == .presented)
        #expect(la.isPresented)
        #expect(la.presentedAt != nil)
    }

    @Test("Lesson relationship and snapshot work")
    func lessonRelationshipAndSnapshotWork() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = Lesson(
            name: "Test Lesson",
            subject: "Math",
            group: "Group A",
            subheading: "A subheading"
        )
        context.insert(lesson)

        let la = LessonAssignment(
            lesson: lesson,
            students: []
        )
        context.insert(la)

        // Mark as presented - should snapshot lesson info
        la.markPresented()

        #expect(la.lessonTitleSnapshot == "Test Lesson")
        #expect(la.lessonSubheadingSnapshot == "A subheading")
    }

    @Test("Student IDs are stored and retrieved correctly")
    func studentIDsWork() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentIDs = [UUID(), UUID(), UUID()]
        let la = LessonAssignment(
            lessonID: UUID(),
            studentIDs: studentIDs
        )
        context.insert(la)
        try context.save()

        // Fetch and verify
        let fetched = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(fetched.count == 1)
        #expect(fetched[0].studentUUIDs.count == 3)

        // Verify all IDs are present
        for id in studentIDs {
            #expect(fetched[0].studentUUIDs.contains(id))
        }
    }
}

#endif
