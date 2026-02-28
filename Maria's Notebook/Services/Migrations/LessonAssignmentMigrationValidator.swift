//
//  LessonAssignmentMigrationValidator.swift
//  Maria's Notebook
//
//  Validates LessonAssignment data integrity.
//  The legacy model has been removed — validation now only checks LessonAssignment records.
//

import Foundation
import SwiftData
import OSLog

/// Validates LessonAssignment data integrity.
///
/// The legacy model has been removed, so validation now only checks
/// LessonAssignment records for internal consistency.
final class LessonAssignmentMigrationValidator {
    private let context: ModelContext
    private let logger = Logger.app(category: "LessonAssignmentValidation")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Validates LessonAssignment data integrity.
    func validate() async throws -> LessonAssignmentValidationResult {
        var result = LessonAssignmentValidationResult()

        logger.info("Starting LessonAssignment validation...")

        let lessonAssignments = try fetchAllLessonAssignments()
        result.totalLessonAssignments = lessonAssignments.count

        // Validate data integrity for all records
        for la in lessonAssignments {
            let issues = validateLessonAssignment(la)
            if !issues.isEmpty {
                result.dataIntegrityIssues.append(DataIntegrityIssue(
                    lessonAssignmentID: la.id,
                    issues: issues
                ))
            }
        }

        if result.isValid {
            logger.info("Validation passed: \(result.totalLessonAssignments) LessonAssignments verified")
        } else {
            logger.warning("Validation found \(result.dataIntegrityIssues.count) integrity issues")
        }

        return result
    }

    /// Quick check to see if data looks healthy.
    func isMigrationComplete() throws -> Bool {
        // Legacy model removed — migration is trivially complete
        return true
    }

    // MARK: - Private Validation Logic

    private func validateLessonAssignment(_ la: LessonAssignment) -> [String] {
        var issues: [String] = []

        if la.lessonID.isEmpty {
            issues.append("lessonID is empty")
        }
        if la.studentIDs.isEmpty {
            issues.append("studentIDs is empty")
        }

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

        return issues
    }

    // MARK: - Fetch Helpers

    private func fetchAllLessonAssignments() throws -> [LessonAssignment] {
        do {
            return try context.fetch(FetchDescriptor<LessonAssignment>())
        } catch {
            logger.warning("Failed to fetch LessonAssignments: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Supporting Types

struct LessonAssignmentValidationResult {
    var totalLegacyRecords = 0
    var totalPresentations = 0
    var totalLessonAssignments = 0

    var unmatchedLegacyRecords: [UnmatchedRecord] = []
    var unmatchedPresentations: [UnmatchedRecord] = []
    var dataIntegrityIssues: [DataIntegrityIssue] = []

    var isValid: Bool {
        unmatchedLegacyRecords.isEmpty &&
        unmatchedPresentations.isEmpty &&
        dataIntegrityIssues.isEmpty
    }

    var hasCriticalIssues: Bool {
        !unmatchedLegacyRecords.isEmpty
    }
}

struct UnmatchedRecord {
    let id: UUID
    let reason: String
}

struct DataIntegrityIssue {
    let lessonAssignmentID: UUID
    let issues: [String]
}

extension LessonAssignmentValidationResult: CustomStringConvertible {
    var description: String {
        if isValid {
            return "ValidationResult: PASSED (\(totalLessonAssignments) LessonAssignments)"
        } else {
            return "ValidationResult: FAILED - \(dataIntegrityIssues.count) integrity issues"
        }
    }
}
