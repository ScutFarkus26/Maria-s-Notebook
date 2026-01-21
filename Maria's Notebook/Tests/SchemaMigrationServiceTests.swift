#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Date Normalization Tests

@Suite("SchemaMigrationService Date Normalization Tests", .serialized)
@MainActor
struct SchemaMigrationServiceDateNormalizationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("normalizeGivenAtToDateOnlyIfNeeded normalizes dates with time component")
    func normalizeGivenAtNormalizesDateWithTime() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag to allow re-run
        UserDefaults.standard.removeObject(forKey: "Migration.givenAtDateOnly.v1")

        // Create a StudentLesson with a time component
        let dateWithTime = TestCalendar.date(year: 2025, month: 1, day: 15, hour: 14, minute: 30, second: 0)
        let sl = makeTestStudentLesson(givenAt: dateWithTime)
        context.insert(sl)
        try context.save()

        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)

        // After normalization, should be start of day
        if let normalizedDate = sl.givenAt {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: normalizedDate)
            let minute = calendar.component(.minute, from: normalizedDate)
            #expect(hour == 0)
            #expect(minute == 0)
        } else {
            Issue.record("givenAt should not be nil")
        }
    }

    @Test("normalizeGivenAtToDateOnlyIfNeeded preserves dates already at start of day")
    func normalizeGivenAtPreservesStartOfDay() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Migration.givenAtDateOnly.v1")

        let startOfDay = TestCalendar.startOfDay(year: 2025, month: 1, day: 15)
        let sl = makeTestStudentLesson(givenAt: startOfDay)
        context.insert(sl)
        try context.save()

        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)

        #expect(sl.givenAt == startOfDay)
    }

    @Test("normalizeGivenAtToDateOnlyIfNeeded handles nil givenAt")
    func normalizeGivenAtHandlesNil() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Migration.givenAtDateOnly.v1")

        let sl = makeTestStudentLesson(givenAt: nil)
        context.insert(sl)
        try context.save()

        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)

        #expect(sl.givenAt == nil)
    }

    @Test("normalizeGivenAtToDateOnlyIfNeeded is idempotent")
    func normalizeGivenAtIsIdempotent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Migration.givenAtDateOnly.v1")

        let dateWithTime = TestCalendar.date(year: 2025, month: 1, day: 15, hour: 14, minute: 30, second: 0)
        let sl = makeTestStudentLesson(givenAt: dateWithTime)
        context.insert(sl)
        try context.save()

        // Run twice
        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)
        let firstResult = sl.givenAt

        // Reset flag to force second run
        UserDefaults.standard.removeObject(forKey: "Migration.givenAtDateOnly.v1")
        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)
        let secondResult = sl.givenAt

        #expect(firstResult == secondResult)
    }
}

// MARK: - GroupTrack Migration Tests

@Suite("SchemaMigrationService GroupTrack Tests", .serialized)
@MainActor
struct SchemaMigrationServiceGroupTrackTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("migrateGroupTracksToDefaultBehaviorIfNeeded sets isExplicitlyDisabled to false")
    func migrateGroupTracksSetsDefaultBehavior() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Migration.groupTracksDefaultBehavior.v1")

        let track = makeTestGroupTrack(subject: "Math", group: "Operations")
        track.isExplicitlyDisabled = true
        context.insert(track)
        try context.save()

        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)

        #expect(track.isExplicitlyDisabled == false)
    }

    @Test("migrateGroupTracksToDefaultBehaviorIfNeeded preserves false value")
    func migrateGroupTracksPreservesFalse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Migration.groupTracksDefaultBehavior.v1")

        let track = makeTestGroupTrack(subject: "Math", group: "Operations")
        track.isExplicitlyDisabled = false
        context.insert(track)
        try context.save()

        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)

        #expect(track.isExplicitlyDisabled == false)
    }

    @Test("migrateGroupTracksToDefaultBehaviorIfNeeded is idempotent")
    func migrateGroupTracksIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset migration flag
        UserDefaults.standard.removeObject(forKey: "Migration.groupTracksDefaultBehavior.v1")

        let track = makeTestGroupTrack(subject: "Math", group: "Operations")
        track.isExplicitlyDisabled = true
        context.insert(track)
        try context.save()

        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
        let firstResult = track.isExplicitlyDisabled

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Migration.groupTracksDefaultBehavior.v1")
        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
        let secondResult = track.isExplicitlyDisabled

        #expect(firstResult == secondResult)
        #expect(secondResult == false)
    }
}

// MARK: - WorkModel Migration Tests

@Suite("SchemaMigrationService WorkModel Tests", .serialized)
@MainActor
struct SchemaMigrationServiceWorkModelTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("migrateWorkContractsToWorkModelsIfNeeded backfills IDs from StudentLesson")
    func migrateWorkContractsBackfillsIDs() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create a StudentLesson
        let lessonID = UUID()
        let studentID = UUID()
        let sl = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID])
        context.insert(sl)
        try context.save()

        // Create a WorkModel that references the StudentLesson but lacks studentID/lessonID
        let work = WorkModel(title: "Test Work", workType: .practice)
        work.studentLessonID = sl.id
        work.studentID = "" // Empty - needs backfill
        work.lessonID = "" // Empty - needs backfill
        context.insert(work)
        try context.save()

        await SchemaMigrationService.migrateWorkContractsToWorkModelsIfNeeded(using: context)

        #expect(work.lessonID == lessonID.uuidString)
        #expect(work.studentID == studentID.uuidString)
    }

    @Test("migrateWorkContractsToWorkModelsIfNeeded skips already populated IDs")
    func migrateWorkContractsSkipsPopulatedIDs() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existingStudentID = UUID()
        let existingLessonID = UUID()

        // Create a WorkModel that already has IDs
        let work = WorkModel(title: "Test Work", workType: .practice)
        work.studentID = existingStudentID.uuidString
        work.lessonID = existingLessonID.uuidString
        context.insert(work)
        try context.save()

        await SchemaMigrationService.migrateWorkContractsToWorkModelsIfNeeded(using: context)

        // IDs should remain unchanged
        #expect(work.studentID == existingStudentID.uuidString)
        #expect(work.lessonID == existingLessonID.uuidString)
    }

    @Test("migrateWorkContractsToWorkModelsIfNeeded handles missing StudentLesson")
    func migrateWorkContractsHandlesMissingStudentLesson() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create a WorkModel with a studentLessonID that doesn't exist
        let work = WorkModel(title: "Test Work", workType: .practice)
        work.studentLessonID = UUID() // Non-existent
        work.studentID = ""
        work.lessonID = ""
        context.insert(work)
        try context.save()

        await SchemaMigrationService.migrateWorkContractsToWorkModelsIfNeeded(using: context)

        // Should not crash, IDs remain empty
        #expect(work.studentID == "")
        #expect(work.lessonID == "")
    }
}

// MARK: - Migration Flag Tests

@Suite("SchemaMigrationService Migration Flag Tests", .serialized)
@MainActor
struct SchemaMigrationServiceMigrationFlagTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
        ])
    }

    @Test("fixCommunityTopicTagsIfNeeded sets migration flag")
    func fixCommunityTopicTagsSetsFlag() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Migration.communityTopicTagsFix.v2")

        SchemaMigrationService.fixCommunityTopicTagsIfNeeded(using: context)

        #expect(MigrationFlag.isComplete(key: "Migration.communityTopicTagsFix.v2") == true)
    }

    @Test("fixStudentLessonStudentIDsIfNeeded sets migration flag")
    func fixStudentLessonStudentIDsSetsFlag() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Migration.studentLessonStudentIDsFix.v1")

        SchemaMigrationService.fixStudentLessonStudentIDsIfNeeded(using: context)

        #expect(MigrationFlag.isComplete(key: "Migration.studentLessonStudentIDsFix.v1") == true)
    }

    @Test("migrateUUIDForeignKeysToStringsIfNeeded sets migration flag")
    func migrateUUIDForeignKeysSetsFlag() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Migration.uuidForeignKeysToStrings.v1")

        SchemaMigrationService.migrateUUIDForeignKeysToStringsIfNeeded(using: context)

        #expect(MigrationFlag.isComplete(key: "Migration.uuidForeignKeysToStrings.v1") == true)
    }
}

// MARK: - AttendanceRecord Migration Tests

@Suite("SchemaMigrationService AttendanceRecord Tests", .serialized)
@MainActor
struct SchemaMigrationServiceAttendanceRecordTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("migrateAttendanceRecordStudentIDToStringIfNeeded is idempotent")
    func migrateAttendanceRecordIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Migration.attendanceRecordStudentIDToString.v1")

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID)
        context.insert(record)
        try context.save()

        // Run migration
        SchemaMigrationService.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)

        // Student ID should be valid UUID string
        #expect(UUID(uuidString: record.studentID) != nil)
    }

    @Test("migrateAttendanceRecordStudentIDToStringIfNeeded skips empty studentID")
    func migrateAttendanceRecordSkipsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset flag
        UserDefaults.standard.removeObject(forKey: "Migration.attendanceRecordStudentIDToString.v1")

        // Create record with empty studentID (edge case)
        let record = AttendanceRecord(
            studentID: UUID(), // Will be converted to string
            date: TestCalendar.date(year: 2025, month: 1, day: 15)
        )
        context.insert(record)
        try context.save()

        // Run migration - should not crash
        SchemaMigrationService.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)

        // Record should still exist
        let fetched = context.safeFetch(FetchDescriptor<AttendanceRecord>())
        #expect(fetched.count == 1)
    }
}

// MARK: - Run All Migrations Tests

@Suite("SchemaMigrationService Run All Tests", .serialized)
@MainActor
struct SchemaMigrationServiceRunAllTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("runAllSchemaMigrations completes without error")
    func runAllSchemaMigrationsCompletes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Reset all flags
        UserDefaults.standard.removeObject(forKey: "Migration.givenAtDateOnly.v1")
        UserDefaults.standard.removeObject(forKey: "Migration.communityTopicTagsFix.v2")
        UserDefaults.standard.removeObject(forKey: "Migration.studentLessonStudentIDsFix.v1")
        UserDefaults.standard.removeObject(forKey: "Migration.uuidForeignKeysToStrings.v1")
        UserDefaults.standard.removeObject(forKey: "Migration.attendanceRecordStudentIDToString.v1")
        UserDefaults.standard.removeObject(forKey: "Migration.groupTracksDefaultBehavior.v1")

        await SchemaMigrationService.runAllSchemaMigrations(using: context)

        // All flags should be set
        #expect(MigrationFlag.isComplete(key: "Migration.communityTopicTagsFix.v2") == true)
        #expect(MigrationFlag.isComplete(key: "Migration.studentLessonStudentIDsFix.v1") == true)
        #expect(MigrationFlag.isComplete(key: "Migration.uuidForeignKeysToStrings.v1") == true)
    }

    @Test("runAllSchemaMigrations is safe to run multiple times")
    func runAllSchemaMigrationsIsSafeToRepeat() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Run multiple times - should not crash or cause issues
        await SchemaMigrationService.runAllSchemaMigrations(using: context)
        await SchemaMigrationService.runAllSchemaMigrations(using: context)
        await SchemaMigrationService.runAllSchemaMigrations(using: context)

        // Should complete without error
    }
}

#endif
