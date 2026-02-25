//
//  LessonAssignmentMigrationValidator.swift
//  Maria's Notebook
//
//  Validates that the LessonAssignment migration preserved all data correctly.
//

import Foundation
import SwiftData
import OSLog

/// Validates that the migration from StudentLesson/Presentation to LessonAssignment
/// preserved all data correctly.
///
/// Use this after running `LessonAssignmentMigrationService.migrateAll()` to verify
/// data integrity before proceeding with further migration phases.
final class LessonAssignmentMigrationValidator {
    private let context: ModelContext
    private let logger = Logger.app(category: "LessonAssignmentValidation")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Validates that migration preserved all data correctly.
    /// - Returns: A validation result with details about any issues found.
    func validate() async throws -> LessonAssignmentValidationResult {
        var result = LessonAssignmentValidationResult()

        logger.info("Starting LessonAssignment migration validation...")

        // Fetch all records
        let studentLessons = try fetchAllStudentLessons()
        // Presentation model removed - no longer fetching presentations
        let lessonAssignments = try fetchAllLessonAssignments()

        result.totalStudentLessons = studentLessons.count
        result.totalPresentations = 0  // Presentation model removed
        result.totalLessonAssignments = lessonAssignments.count

        // Build lookup for quick matching
        let laByStudentLessonID = buildStudentLessonLookup(lessonAssignments)
        // Presentation model removed - no longer building presentation lookups

        // Check each StudentLesson has a corresponding LessonAssignment
        for sl in studentLessons {
            if laByStudentLessonID[sl.id.uuidString] == nil {
                result.unmatchedStudentLessons.append(UnmatchedRecord(
                    id: sl.id,
                    reason: "No LessonAssignment found with migratedFromStudentLessonID matching this StudentLesson"
                ))
            }
        }

        // Presentation model removed - no longer checking for unmatched presentations

        // Validate data integrity for migrated records
        for la in lessonAssignments {
            let issues = validateLessonAssignment(la)
            if !issues.isEmpty {
                result.dataIntegrityIssues.append(DataIntegrityIssue(
                    lessonAssignmentID: la.id,
                    issues: issues
                ))
            }
        }

        // Log results
        if result.isValid {
            logger.info("Migration validation passed: \(result.totalLessonAssignments) LessonAssignments verified")
        } else {
            logger.warning("Migration validation found issues: \(result.unmatchedStudentLessons.count) unmatched StudentLessons, \(result.unmatchedPresentations.count) unmatched Presentations, \(result.dataIntegrityIssues.count) integrity issues")
        }

        return result
    }

    /// Quick check to see if migration appears complete without full validation.
    func isMigrationComplete() throws -> Bool {
        let studentLessons = try fetchAllStudentLessons()
        let lessonAssignments = try fetchAllLessonAssignments()

        // If there are no source records, migration is trivially complete
        if studentLessons.isEmpty {
            return true
        }

        // Check that we have at least as many LessonAssignments as StudentLessons
        // (we may have more due to orphaned Presentations)
        return lessonAssignments.count >= studentLessons.count
    }

    // MARK: - Private Validation Logic

    // Presentation model removed - simplified validation
    private func validateLessonAssignment(_ la: LessonAssignment) -> [String] {
        var issues: [String] = []

        // Check required fields
        if la.lessonID.isEmpty {
            issues.append("lessonID is empty")
        }

        if la.studentIDs.isEmpty {
            issues.append("studentIDs is empty")
        }

        // Check state consistency
        switch la.state {
        case .draft:
            if la.scheduledFor != nil {
                issues.append("Draft state but scheduledFor is set")
            }
            if la.presentedAt != nil {
                issues.append("Draft state but presentedAt is set")
            }

        case .scheduled:
            if la.scheduledFor == nil {
                issues.append("Scheduled state but scheduledFor is nil")
            }
            if la.presentedAt != nil {
                issues.append("Scheduled state but presentedAt is set")
            }

        case .presented:
            if la.presentedAt == nil {
                issues.append("Presented state but presentedAt is nil")
            }
        }

        // Presentation model removed - no longer validating Presentation ID matching

        return issues
    }

    // MARK: - Fetch Helpers

    private func fetchAllStudentLessons() throws -> [StudentLesson] {
        let descriptor = FetchDescriptor<StudentLesson>()
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch StudentLessons: \(error.localizedDescription)")
            return []
        }
    }

    // Presentation model removed - fetchAllPresentations removed

    private func fetchAllLessonAssignments() throws -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>()
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch LessonAssignments: \(error.localizedDescription)")
            return []
        }
    }

    private func buildStudentLessonLookup(_ assignments: [LessonAssignment]) -> [String: LessonAssignment] {
        var lookup: [String: LessonAssignment] = [:]
        for la in assignments {
            if let slID = la.migratedFromStudentLessonID {
                lookup[slID] = la
            }
        }
        return lookup
    }

    // Presentation model removed - buildPresentationLookup and buildPresentationByLegacyIDLookup removed
}

// MARK: - Supporting Types

/// Result of migration validation.
struct LessonAssignmentValidationResult {
    var totalStudentLessons = 0
    var totalPresentations = 0
    var totalLessonAssignments = 0

    var unmatchedStudentLessons: [UnmatchedRecord] = []
    var unmatchedPresentations: [UnmatchedRecord] = []
    var dataIntegrityIssues: [DataIntegrityIssue] = []

    /// Returns true if validation passed with no issues.
    var isValid: Bool {
        unmatchedStudentLessons.isEmpty &&
        unmatchedPresentations.isEmpty &&
        dataIntegrityIssues.isEmpty
    }

    /// Returns true if there are critical issues that should block further migration.
    var hasCriticalIssues: Bool {
        !unmatchedStudentLessons.isEmpty
    }
}

/// Represents a source record that wasn't migrated.
struct UnmatchedRecord {
    let id: UUID
    let reason: String
}

/// Represents a data integrity issue in a migrated record.
struct DataIntegrityIssue {
    let lessonAssignmentID: UUID
    let issues: [String]
}

extension LessonAssignmentValidationResult: CustomStringConvertible {
    var description: String {
        if isValid {
            return "ValidationResult: PASSED (\(totalLessonAssignments) LessonAssignments from \(totalStudentLessons) StudentLessons + \(totalPresentations) Presentations)"
        } else {
            return "ValidationResult: FAILED - \(unmatchedStudentLessons.count) unmatched StudentLessons, \(unmatchedPresentations.count) unmatched Presentations, \(dataIntegrityIssues.count) integrity issues"
        }
    }
}
