//
//  LessonAssignmentMigrationService.swift
//  Maria's Notebook
//
//  Originally migrated StudentLesson records to LessonAssignment.
//  StudentLesson has been removed — migration is complete.
//  This service is kept for API compatibility with DataMigrations.
//

import Foundation
import SwiftData
import OSLog

/// Service responsible for migrating legacy records to the unified LessonAssignment model.
///
/// The StudentLesson model has been fully removed. This service now only exists
/// so that existing migration flags remain valid and callers don't break.
/// All methods return immediately with no work done.
nonisolated final class LessonAssignmentMigrationService {
    private let context: ModelContext
    private let logger = Logger.app(category: "LessonAssignmentMigration")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Migration is complete — StudentLesson model has been removed.
    func migrateAll() async throws -> LessonAssignmentMigrationResult {
        logger.debug("LessonAssignment migration skipped — StudentLesson model removed")
        return LessonAssignmentMigrationResult()
    }

    /// Migration is complete — returns nil (already done).
    func migrateIfNeeded() async throws -> LessonAssignmentMigrationResult? {
        let flagKey = "Migration.lessonAssignment.v1"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
        return nil
    }

    /// V2 migration is complete — returns nil (already done).
    func migrateIfNeededV2() async throws -> LessonAssignmentMigrationResult? {
        let flagKey = "Migration.lessonAssignment.v2"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
        return nil
    }
}

// MARK: - Supporting Types

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
