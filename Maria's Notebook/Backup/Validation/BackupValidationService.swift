import Foundation
import SwiftData

/// Validates backup data before restore to catch issues early
/// Checks foreign key references, data constraints, and relationship integrity
///
/// Split into multiple files for maintainability:
/// - BackupValidationService.swift (this file) - Core validation orchestration
/// - BackupValidationTypes.swift - Result types (ValidationResult, EntityTypeValidation, etc.)
/// - BackupValidationService+ForeignKeys.swift - Foreign key validation method
@MainActor
public final class BackupValidationService {

    // MARK: - Validation

    /// Validates a backup payload before attempting restore
    /// - Parameters:
    ///   - payload: The backup payload to validate
    ///   - modelContext: Optional model context for cross-checking with existing data
    ///   - mode: The restore mode (merge or replace)
    /// - Returns: Validation result with errors, warnings, and recommendations
    public func validate(
        payload: BackupPayload,
        against modelContext: ModelContext?,
        mode: BackupService.RestoreMode
    ) async throws -> ValidationResult {

        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        var recommendations: [String] = []

        // Phase 1: Structural validation
        errors.append(contentsOf: validateStructure(payload))

        // Phase 2: Foreign key validation
        errors.append(contentsOf: validateForeignKeys(payload))

        // Phase 3: Data constraint validation
        errors.append(contentsOf: validateDataConstraints(payload))

        // Phase 4: Relationship consistency
        errors.append(contentsOf: validateRelationships(payload))

        // Phase 5: Duplicate detection
        let duplicates = detectDuplicates(payload)
        if !duplicates.isEmpty {
            warnings.append(ValidationWarning(
                message: "Found \(duplicates.count) duplicate entity IDs",
                recommendation: "Backup will automatically deduplicate during import"
            ))
        }

        // Phase 6: Cross-reference with existing data (if in merge mode)
        if mode == .merge, let context = modelContext {
            let conflicts = try await detectConflicts(payload, context: context)
            if !conflicts.isEmpty {
                warnings.append(ValidationWarning(
                    message: "Found \(conflicts.count) potential conflicts with existing data",
                    recommendation: "Review conflicts in the restore preview"
                ))
            }
        }

        // Phase 7: Generate entity type details
        let entityTypeDetails = generateEntityTypeDetails(payload, mode: mode, context: modelContext)

        // Phase 8: Generate recommendations
        recommendations.append(contentsOf: generateRecommendations(payload, errors: errors, warnings: warnings))

        let isValid = errors.filter { $0.severity == .critical || $0.severity == .error }.isEmpty

        return ValidationResult(
            isValid: isValid,
            errors: errors,
            warnings: warnings,
            recommendations: recommendations,
            entityTypeDetails: entityTypeDetails
        )
    }

    // MARK: - Structural Validation

    private func validateStructure(_ payload: BackupPayload) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Check for empty required fields in critical entities
        for student in payload.students {
            if student.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(ValidationError(
                    entityType: "Student",
                    entityID: student.id,
                    field: "firstName",
                    message: "Student has empty first name",
                    severity: .error
                ))
            }

            if student.birthday > Date() {
                errors.append(ValidationError(
                    entityType: "Student",
                    entityID: student.id,
                    field: "birthday",
                    message: "Student birthday is in the future",
                    severity: .error
                ))
            }
        }

        for lesson in payload.lessons {
            if lesson.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(ValidationError(
                    entityType: "Lesson",
                    entityID: lesson.id,
                    field: "name",
                    message: "Lesson has empty name",
                    severity: .error
                ))
            }
        }

        return errors
    }

    // MARK: - Data Constraint Validation

    private func validateDataConstraints(_ payload: BackupPayload) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Validate date constraints
        for sl in payload.legacyPresentations {
            if let scheduled = sl.scheduledFor, let given = sl.givenAt {
                if given < scheduled {
                    errors.append(ValidationError(
                        entityType: "LegacyPresentation",
                        entityID: sl.id,
                        field: "givenAt",
                        message: "Given date (\(given)) is before scheduled date (\(scheduled))",
                        severity: .warning
                    ))
                }
            }
        }

        // Validate attendance status values
        let validStatuses = ["present", "absent", "tardy", "excused"]
        for record in payload.attendance {
            if !validStatuses.contains(record.status.lowercased()) {
                errors.append(ValidationError(
                    entityType: "AttendanceRecord",
                    entityID: record.id,
                    field: "status",
                    message: "Invalid attendance status: '\(record.status)'",
                    severity: .error
                ))
            }
        }

        // Validate student level values
        for student in payload.students {
            if student.level != .lower && student.level != .upper {
                errors.append(ValidationError(
                    entityType: "Student",
                    entityID: student.id,
                    field: "level",
                    message: "Invalid student level",
                    severity: .error
                ))
            }
        }

        return errors
    }

    // MARK: - Relationship Validation

    private func validateRelationships(_ payload: BackupPayload) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Validate circular references in student next lessons
        let lessonIDs = Set(payload.lessons.map { $0.id })
        for student in payload.students {
            for nextLessonID in student.nextLessons {
                if !lessonIDs.contains(nextLessonID) {
                    errors.append(ValidationError(
                        entityType: "Student",
                        entityID: student.id,
                        field: "nextLessons",
                        message: "References non-existent lesson in nextLessons: \(nextLessonID)",
                        severity: .warning
                    ))
                }
            }
        }

        // Validate project sessions reference valid weeks
        let weekIDs = Set(payload.projectTemplateWeeks.map { $0.id })
        for session in payload.projectSessions {
            if let weekID = session.templateWeekID, !weekIDs.contains(weekID) {
                errors.append(ValidationError(
                    entityType: "ProjectSession",
                    entityID: session.id,
                    field: "templateWeekID",
                    message: "References non-existent template week: \(weekID)",
                    severity: .warning
                ))
            }
        }

        return errors
    }

    // MARK: - Duplicate Detection

    private func detectDuplicates(_ payload: BackupPayload) -> [UUID] {
        var allIDs: [UUID] = []
        var duplicates: [UUID] = []

        allIDs.append(contentsOf: payload.students.map { $0.id })
        allIDs.append(contentsOf: payload.lessons.map { $0.id })
        allIDs.append(contentsOf: payload.legacyPresentations.map { $0.id })
        allIDs.append(contentsOf: payload.lessonAssignments.map { $0.id })
        allIDs.append(contentsOf: payload.notes.map { $0.id })
        allIDs.append(contentsOf: payload.nonSchoolDays.map { $0.id })
        allIDs.append(contentsOf: payload.schoolDayOverrides.map { $0.id })
        allIDs.append(contentsOf: payload.studentMeetings.map { $0.id })
        allIDs.append(contentsOf: payload.communityTopics.map { $0.id })
        allIDs.append(contentsOf: payload.proposedSolutions.map { $0.id })
        allIDs.append(contentsOf: payload.communityAttachments.map { $0.id })
        allIDs.append(contentsOf: payload.attendance.map { $0.id })
        allIDs.append(contentsOf: payload.workCompletions.map { $0.id })

        var seen = Set<UUID>()
        for id in allIDs {
            if seen.contains(id) {
                duplicates.append(id)
            }
            seen.insert(id)
        }

        return duplicates
    }

    // MARK: - Conflict Detection

    private func detectConflicts(_ payload: BackupPayload, context: ModelContext) async throws -> [UUID] {
        var conflicts: [UUID] = []

        // Check for ID conflicts with existing data
        for student in payload.students {
            if try entityExists(Student.self, id: student.id, in: context) {
                conflicts.append(student.id)
            }
        }

        for lesson in payload.lessons {
            if try entityExists(Lesson.self, id: lesson.id, in: context) {
                conflicts.append(lesson.id)
            }
        }

        // Add more as needed...

        return conflicts
    }

    private func entityExists<T: PersistentModel>(_ type: T.Type, id: UUID, in context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { entity in
            entity.persistentModelID.hashValue == id.hashValue
        })
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        return !results.isEmpty
    }

    // MARK: - Entity Type Details

    private func generateEntityTypeDetails(
        _ payload: BackupPayload,
        mode: BackupService.RestoreMode,
        context: ModelContext?
    ) -> [String: EntityTypeValidation] {
        var details: [String: EntityTypeValidation] = [:]

        // Count entities from each collection in payload
        var entityCounts: [(String, Int)] = []
        entityCounts.append(("Student", payload.students.count))
        entityCounts.append(("Lesson", payload.lessons.count))
        entityCounts.append(("LegacyPresentation", payload.legacyPresentations.count))
        entityCounts.append(("LessonAssignment", payload.lessonAssignments.count))
        entityCounts.append(("Note", payload.notes.count))
        entityCounts.append(("NonSchoolDay", payload.nonSchoolDays.count))
        entityCounts.append(("SchoolDayOverride", payload.schoolDayOverrides.count))
        entityCounts.append(("StudentMeeting", payload.studentMeetings.count))
        entityCounts.append(("CommunityTopic", payload.communityTopics.count))
        entityCounts.append(("ProposedSolution", payload.proposedSolutions.count))
        entityCounts.append(("CommunityAttachment", payload.communityAttachments.count))
        entityCounts.append(("AttendanceRecord", payload.attendance.count))
        entityCounts.append(("WorkCompletionRecord", payload.workCompletions.count))
        entityCounts.append(("Project", payload.projects.count))
        entityCounts.append(("ProjectAssignmentTemplate", payload.projectAssignmentTemplates.count))
        entityCounts.append(("ProjectSession", payload.projectSessions.count))
        entityCounts.append(("ProjectRole", payload.projectRoles.count))
        entityCounts.append(("ProjectTemplateWeek", payload.projectTemplateWeeks.count))
        entityCounts.append(("ProjectWeekRoleAssignment", payload.projectWeekRoleAssignments.count))

        for (entityType, count) in entityCounts where count > 0 {
            let willInsert: Int
            let willUpdate: Int
            let willSkip: Int
            let willDelete: Int

            switch mode {
            case .replace:
                willInsert = count
                willUpdate = 0
                willSkip = 0
                willDelete = 0  // Would need context to calculate
            case .merge:
                // Simplified - would need to actually check for duplicates
                willInsert = count
                willUpdate = 0
                willSkip = 0
                willDelete = 0
            }

            details[entityType] = EntityTypeValidation(
                entityType: entityType,
                willInsert: willInsert,
                willUpdate: willUpdate,
                willSkip: willSkip,
                willDelete: willDelete,
                issues: []
            )
        }

        return details
    }

    // MARK: - Recommendations

    private func generateRecommendations(
        _ payload: BackupPayload,
        errors: [ValidationError],
        warnings: [ValidationWarning]
    ) -> [String] {
        var recommendations: [String] = []

        let criticalErrors = errors.filter { $0.severity == .critical }
        if !criticalErrors.isEmpty {
            recommendations.append("Critical errors detected. Fix these issues before attempting restore.")
        }

        let errorCount = errors.filter { $0.severity == .error }
        if !errorCount.isEmpty {
            recommendations.append("Found \(errorCount.count) validation errors. Review before proceeding.")
        }

        if !warnings.isEmpty {
            recommendations.append("Review \(warnings.count) warnings before proceeding with restore.")
        }

        let totalEntities = payload.students.count + payload.lessons.count + payload.notes.count
        if totalEntities > BatchingConstants.largeDatasetThreshold {
            recommendations.append("Large backup detected (\(totalEntities) entities). Restore may take several minutes.")
        }

        return recommendations
    }
}
