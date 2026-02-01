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
@MainActor
final class LessonAssignmentMigrationValidator {
    private let context: ModelContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "LessonAssignmentValidation")

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
        let presentations = try fetchAllPresentations()
        let lessonAssignments = try fetchAllLessonAssignments()

        result.totalStudentLessons = studentLessons.count
        result.totalPresentations = presentations.count
        result.totalLessonAssignments = lessonAssignments.count

        // Build lookup for quick matching
        let laByStudentLessonID = buildStudentLessonLookup(lessonAssignments)
        let laByPresentationID = buildPresentationLookup(lessonAssignments)
        let presentationByLegacyID = buildPresentationByLegacyIDLookup(presentations)

        // Check each StudentLesson has a corresponding LessonAssignment
        for sl in studentLessons {
            if laByStudentLessonID[sl.id.uuidString] == nil {
                result.unmatchedStudentLessons.append(UnmatchedRecord(
                    id: sl.id,
                    reason: "No LessonAssignment found with migratedFromStudentLessonID matching this StudentLesson"
                ))
            }
        }

        // Check each Presentation is accounted for
        for p in presentations {
            let matchedViaPresentation = laByPresentationID[p.id.uuidString] != nil
            let matchedViaStudentLesson: Bool

            if let legacyID = p.legacyStudentLessonID, !legacyID.isEmpty {
                // This Presentation is linked to a StudentLesson
                matchedViaStudentLesson = laByStudentLessonID[legacyID] != nil
            } else {
                matchedViaStudentLesson = false
            }

            if !matchedViaPresentation && !matchedViaStudentLesson {
                result.unmatchedPresentations.append(UnmatchedRecord(
                    id: p.id,
                    reason: "No LessonAssignment found for this Presentation (orphaned)"
                ))
            }
        }

        // Validate data integrity for migrated records
        for la in lessonAssignments {
            let issues = validateLessonAssignment(
                la,
                presentationByLegacyID: presentationByLegacyID
            )
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

    private func validateLessonAssignment(
        _ la: LessonAssignment,
        presentationByLegacyID: [String: Presentation]
    ) -> [String] {
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

        // If migrated from StudentLesson, verify key fields match
        if let slID = la.migratedFromStudentLessonID {
            // Check if we can find the linked Presentation
            if let pID = la.migratedFromPresentationID {
                // Verify the Presentation's legacyStudentLessonID matches
                if let p = presentationByLegacyID[slID] {
                    if p.id.uuidString != pID {
                        issues.append("Presentation ID mismatch: expected \(pID), found \(p.id.uuidString) for StudentLesson \(slID)")
                    }
                }
            }
        }

        return issues
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

    private func fetchAllLessonAssignments() throws -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>()
        return (try? context.fetch(descriptor)) ?? []
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

    private func buildPresentationLookup(_ assignments: [LessonAssignment]) -> [String: LessonAssignment] {
        var lookup: [String: LessonAssignment] = [:]
        for la in assignments {
            if let pID = la.migratedFromPresentationID {
                lookup[pID] = la
            }
        }
        return lookup
    }

    private func buildPresentationByLegacyIDLookup(_ presentations: [Presentation]) -> [String: Presentation] {
        var lookup: [String: Presentation] = [:]
        for p in presentations {
            if let legacyID = p.legacyStudentLessonID, !legacyID.isEmpty {
                lookup[legacyID] = p
            }
        }
        return lookup
    }
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
