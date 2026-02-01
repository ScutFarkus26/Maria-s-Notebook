//
//  LessonAssignmentMigrationService.swift
//  Maria's Notebook
//
//  Migrates StudentLesson and Presentation records to the new unified LessonAssignment model.
//

import Foundation
import SwiftData
import OSLog

/// Service responsible for migrating StudentLesson and Presentation records
/// to the new unified LessonAssignment model.
///
/// This migration is:
/// - **Idempotent**: Safe to run multiple times; already-migrated records are skipped.
/// - **Non-destructive**: Original StudentLesson and Presentation records are preserved.
/// - **Traceable**: Each LessonAssignment records which source record(s) it came from.
@MainActor
final class LessonAssignmentMigrationService {
    private let context: ModelContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "LessonAssignmentMigration")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Migrates all StudentLessons and Presentations to LessonAssignments.
    /// Safe to run multiple times (idempotent).
    ///
    /// - Returns: A result summarizing what was migrated.
    func migrateAll() async throws -> LessonAssignmentMigrationResult {
        var result = LessonAssignmentMigrationResult()

        logger.info("Starting LessonAssignment migration...")

        // Build lookup tables for efficiency
        let presentations = try fetchAllPresentations()
        let presentationByLegacyID = buildPresentationLookup(presentations)
        let existingMigrations = try fetchExistingMigrationTracking()

        logger.info("Found \(presentations.count) Presentations, \(existingMigrations.studentLessonIDs.count) already-migrated StudentLessons")

        // Step 1: Migrate all StudentLessons
        let studentLessons = try fetchAllStudentLessons()
        for (index, sl) in studentLessons.enumerated() {
            // Yield periodically to avoid blocking
            if index % 50 == 0 && index > 0 {
                await Task.yield()
            }

            let migrated = try migrateStudentLesson(
                sl,
                linkedPresentation: presentationByLegacyID[sl.id.uuidString],
                existingMigrations: existingMigrations
            )

            if migrated {
                result.studentLessonsMigrated += 1
            } else {
                result.studentLessonsSkipped += 1
            }
        }

        // Step 2: Migrate orphaned Presentations (those without a linked StudentLesson)
        for (index, p) in presentations.enumerated() {
            if index % 50 == 0 && index > 0 {
                await Task.yield()
            }

            let migrated = try migrateOrphanedPresentation(p, existingMigrations: existingMigrations)

            if migrated {
                result.presentationsMigrated += 1
            } else {
                result.presentationsSkipped += 1
            }
        }

        // Save all changes
        if result.totalMigrated > 0 {
            context.safeSave()
            logger.info("LessonAssignment migration complete: \(result.studentLessonsMigrated) StudentLessons, \(result.presentationsMigrated) orphaned Presentations migrated")
        } else {
            logger.info("LessonAssignment migration complete: no new records to migrate")
        }

        return result
    }

    /// Runs the migration if it hasn't been completed yet.
    /// Uses MigrationFlag for idempotency at the app level.
    func migrateIfNeeded() async throws -> LessonAssignmentMigrationResult? {
        let flagKey = "Migration.lessonAssignment.v1"

        guard !MigrationFlag.isComplete(key: flagKey) else {
            logger.debug("LessonAssignment migration already complete (flag set)")
            return nil
        }

        let result = try await migrateAll()

        // Only mark complete if we actually processed something or there was nothing to process
        MigrationFlag.markComplete(key: flagKey)

        return result
    }

    // MARK: - Private Migration Logic

    /// Migrates a single StudentLesson to LessonAssignment.
    /// - Returns: `true` if migrated, `false` if already exists.
    private func migrateStudentLesson(
        _ sl: StudentLesson,
        linkedPresentation: Presentation?,
        existingMigrations: ExistingMigrationTracking
    ) throws -> Bool {
        // Check if already migrated
        if existingMigrations.studentLessonIDs.contains(sl.id.uuidString) {
            return false
        }

        // Determine state based on StudentLesson flags and linked Presentation
        let state: LessonAssignmentState
        let presentedAt: Date?

        if sl.isPresented || sl.givenAt != nil || linkedPresentation != nil {
            state = .presented
            presentedAt = linkedPresentation?.presentedAt ?? sl.givenAt ?? Date()
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
            trackID: linkedPresentation?.trackID,
            trackStepID: linkedPresentation?.trackStepID
        )

        // Copy snapshots from Presentation if available
        // Note: Presentation uses lessonSubtitleSnapshot, but we rename to lessonSubheadingSnapshot
        if let p = linkedPresentation {
            la.lessonTitleSnapshot = p.lessonTitleSnapshot
            la.lessonSubheadingSnapshot = p.lessonSubtitleSnapshot
        } else if state == .presented, let lesson = sl.lesson {
            // No linked Presentation, but marked as presented - snapshot from current lesson
            la.lessonTitleSnapshot = lesson.name
            la.lessonSubheadingSnapshot = lesson.subheading
        }

        // Track migration source
        la.migratedFromStudentLessonID = sl.id.uuidString
        la.migratedFromPresentationID = linkedPresentation?.id.uuidString

        context.insert(la)

        logger.debug("Migrated StudentLesson \(sl.id) -> LessonAssignment \(la.id) (state: \(state.rawValue))")

        return true
    }

    /// Migrates a Presentation that has no linked StudentLesson.
    /// - Returns: `true` if migrated, `false` if skipped (has linked StudentLesson or already migrated).
    private func migrateOrphanedPresentation(
        _ p: Presentation,
        existingMigrations: ExistingMigrationTracking
    ) throws -> Bool {
        // Skip if has a linked StudentLesson (already handled in StudentLesson migration)
        if let legacyID = p.legacyStudentLessonID, !legacyID.isEmpty {
            // Check if that StudentLesson actually exists
            let slExists = try checkStudentLessonExists(id: legacyID)
            if slExists {
                return false // Will be migrated via StudentLesson path
            }
            // StudentLesson doesn't exist - this is truly orphaned, migrate it
        }

        // Check if already migrated via presentation ID
        if existingMigrations.presentationIDs.contains(p.id.uuidString) {
            return false
        }

        // Create new LessonAssignment for orphaned Presentation
        let la = LessonAssignment(
            id: UUID(),
            createdAt: p.createdAt,
            state: .presented,
            scheduledFor: nil,
            presentedAt: p.presentedAt,
            lessonID: UUID(uuidString: p.lessonID) ?? UUID(),
            studentIDs: p.studentIDs.compactMap { UUID(uuidString: $0) },
            lesson: nil, // Will need to be resolved later
            trackID: p.trackID,
            trackStepID: p.trackStepID
        )

        la.lessonTitleSnapshot = p.lessonTitleSnapshot
        la.lessonSubheadingSnapshot = p.lessonSubtitleSnapshot  // Rename from subtitle to subheading
        la.migratedFromPresentationID = p.id.uuidString

        context.insert(la)

        logger.debug("Migrated orphaned Presentation \(p.id) -> LessonAssignment \(la.id)")

        return true
    }

    // MARK: - Fetch Helpers

    private func fetchAllStudentLessons() throws -> [StudentLesson] {
        let descriptor = FetchDescriptor<StudentLesson>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchAllPresentations() throws -> [Presentation] {
        let descriptor = FetchDescriptor<Presentation>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func buildPresentationLookup(_ presentations: [Presentation]) -> [String: Presentation] {
        var lookup: [String: Presentation] = [:]
        for p in presentations {
            if let legacyID = p.legacyStudentLessonID, !legacyID.isEmpty {
                lookup[legacyID] = p
            }
        }
        return lookup
    }

    private func fetchExistingMigrationTracking() throws -> ExistingMigrationTracking {
        let descriptor = FetchDescriptor<LessonAssignment>()
        let existing = (try? context.fetch(descriptor)) ?? []

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

    private func checkStudentLessonExists(id: String) throws -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == uuid }
        )
        let results = (try? context.fetch(descriptor)) ?? []
        return !results.isEmpty
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
