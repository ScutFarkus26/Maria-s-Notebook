//
//  LessonAssignmentMigrationService.swift
//  Maria's Notebook
//
//  Migrates StudentLesson records to the new unified LessonAssignment model.
//  Note: Presentation model has been removed. This service now only migrates StudentLessons.
//

import Foundation
import SwiftData
import OSLog

/// Service responsible for migrating StudentLesson records
/// to the new unified LessonAssignment model.
///
/// This migration is:
/// - **Idempotent**: Safe to run multiple times; already-migrated records are skipped.
/// - **Non-destructive**: Original StudentLesson records are preserved.
/// - **Traceable**: Each LessonAssignment records which source record(s) it came from.
///
/// Note: The Presentation model has been removed. This service now only migrates
/// StudentLessons to LessonAssignments.
final class LessonAssignmentMigrationService {
    private let context: ModelContext
    private let logger = Logger.app(category: "LessonAssignmentMigration")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Migrates all StudentLessons to LessonAssignments.
    /// Safe to run multiple times (idempotent).
    ///
    /// - Returns: A result summarizing what was migrated.
    func migrateAll() async throws -> LessonAssignmentMigrationResult {
        var result = LessonAssignmentMigrationResult()

        logger.info("Starting LessonAssignment migration...")

        // Fetch existing migration tracking
        let existingMigrations = try fetchExistingMigrationTracking()

        logger.info("Found \(existingMigrations.studentLessonIDs.count) already-migrated StudentLessons")

        // Migrate all StudentLessons
        let studentLessons = try fetchAllStudentLessons()
        for (index, sl) in studentLessons.enumerated() {
            // Yield periodically to avoid blocking
            if index % 50 == 0 && index > 0 {
                await Task.yield()
            }

            let migrated = try migrateStudentLesson(
                sl,
                existingMigrations: existingMigrations
            )

            if migrated {
                result.studentLessonsMigrated += 1
            } else {
                result.studentLessonsSkipped += 1
            }
        }

        // Note: Presentation migration removed - model no longer exists

        // Save all changes
        if result.totalMigrated > 0 {
            context.safeSave()
            logger.info("LessonAssignment migration complete: \(result.studentLessonsMigrated) StudentLessons migrated")
        } else {
            logger.info("LessonAssignment migration complete: no new records to migrate")
        }

        return result
    }

    /// Runs the migration if it hasn't been completed yet.
    /// Uses MigrationFlag for idempotency at the app level.
    func migrateIfNeeded() async throws -> LessonAssignmentMigrationResult? {
        let flagKey = "Migration.lessonAssignment.v1"

        // Check if we have any LessonAssignment records
        let existingCount: Int
        do {
            existingCount = try context.fetchCount(FetchDescriptor<LessonAssignment>())
        } catch {
            logger.error("Failed to check existing LessonAssignment count: \(error.localizedDescription)")
            existingCount = 0
        }

        // If flag is set but we have no records, reset the flag and re-run
        if MigrationFlag.isComplete(key: flagKey) && existingCount == 0 {
            logger.warning("Migration flag was set but no LessonAssignment records exist - resetting flag to re-run migration")
            MigrationFlag.reset(key: flagKey)
        }

        guard !MigrationFlag.isComplete(key: flagKey) else {
            logger.debug("LessonAssignment migration already complete (flag set, \(existingCount) records exist)")
            return nil
        }

        let result = try await migrateAll()

        // Only mark complete if we actually processed something or there was nothing to process
        MigrationFlag.markComplete(key: flagKey)

        return result
    }

    // MARK: - Private Migration Logic

    /// Migrates a single StudentLesson to LessonAssignment.
    /// - Returns: `true` if migrated, `false` if already exists or corrupted.
    private func migrateStudentLesson(
        _ sl: StudentLesson,
        existingMigrations: ExistingMigrationTracking
    ) throws -> Bool {
        // Check if already migrated
        if existingMigrations.studentLessonIDs.contains(sl.id.uuidString) {
            return false
        }

        // Skip corrupted StudentLessons with empty studentIDs - they provide no value
        if sl.studentIDs.isEmpty {
            logger.warning("Skipping StudentLesson \(sl.id) - empty studentIDs (corrupted data)")
            return false
        }

        // Determine state based on StudentLesson flags
        let state: LessonAssignmentState
        let presentedAt: Date?

        if sl.isPresented || sl.givenAt != nil {
            state = .presented
            presentedAt = sl.givenAt ?? Date()
        } else if sl.scheduledFor != nil {
            state = .scheduled
            presentedAt = nil
        } else {
            state = .draft
            presentedAt = nil
        }

        // Create new LessonAssignment
        let la = LessonAssignment(
            id: UUID(), // New ID for clean slate
            createdAt: sl.createdAt,
            state: state,
            scheduledFor: sl.scheduledFor,
            presentedAt: presentedAt,
            lessonID: UUID(uuidString: sl.lessonID) ?? UUID(),
            studentIDs: sl.studentIDs.compactMap { UUID(uuidString: $0) },
            lesson: sl.lesson,
            needsPractice: sl.needsPractice,
            needsAnotherPresentation: sl.needsAnotherPresentation,
            followUpWork: sl.followUpWork,
            notes: sl.notes,
            trackID: nil,
            trackStepID: nil
        )

        // Set snapshots if presented and has lesson
        if state == .presented, let lesson = sl.lesson {
            la.lessonTitleSnapshot = lesson.name
            la.lessonSubheadingSnapshot = lesson.subheading
        }

        // Track migration source
        la.migratedFromStudentLessonID = sl.id.uuidString

        context.insert(la)

        logger.debug("Migrated StudentLesson \(sl.id) -> LessonAssignment \(la.id) (state: \(state.rawValue))")

        return true
    }

    // MARK: - Fetch Helpers

    private func fetchAllStudentLessons() throws -> [StudentLesson] {
        let descriptor = FetchDescriptor<StudentLesson>()
        do {
            return try context.fetch(descriptor)
        } catch {
            print("⚠️ [\(#function)] Failed to fetch StudentLessons: \(error)")
            return []
        }
    }

    private func fetchExistingMigrationTracking() throws -> ExistingMigrationTracking {
        let descriptor = FetchDescriptor<LessonAssignment>()
        let existing: [LessonAssignment]
        do {
            existing = try context.fetch(descriptor)
        } catch {
            print("⚠️ [\(#function)] Failed to fetch existing LessonAssignments: \(error)")
            existing = []
        }

        var studentLessonIDs = Set<String>()
        var presentationIDs = Set<String>()

        for la in existing {
            if let slID = la.migratedFromStudentLessonID {
                studentLessonIDs.insert(slID)
            }
            if let pID = la.migratedFromPresentationID {
                presentationIDs.insert(pID)
            }
        }

        return ExistingMigrationTracking(
            studentLessonIDs: studentLessonIDs,
            presentationIDs: presentationIDs
        )
    }
}

// MARK: - Supporting Types

/// Tracks which records have already been migrated.
private struct ExistingMigrationTracking {
    let studentLessonIDs: Set<String>
    let presentationIDs: Set<String>
}

/// Result of a migration run.
struct LessonAssignmentMigrationResult {
    var studentLessonsMigrated = 0
    var studentLessonsSkipped = 0
    var presentationsMigrated = 0
    var presentationsSkipped = 0

    var totalMigrated: Int {
        studentLessonsMigrated + presentationsMigrated
    }

    var totalSkipped: Int {
        studentLessonsSkipped + presentationsSkipped
    }
}

extension LessonAssignmentMigrationResult: CustomStringConvertible {
    var description: String {
        "LessonAssignmentMigrationResult(studentLessons: \(studentLessonsMigrated) migrated / \(studentLessonsSkipped) skipped, presentations: \(presentationsMigrated) migrated / \(presentationsSkipped) skipped)"
    }
}
