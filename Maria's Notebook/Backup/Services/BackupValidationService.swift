import Foundation
import SwiftData

/// Validates backup data before restore to catch issues early
/// Checks foreign key references, data constraints, and relationship integrity
@MainActor
public final class BackupValidationService {
    
    // MARK: - Types
    
    public struct ValidationResult {
        public var isValid: Bool
        public var errors: [ValidationError]
        public var warnings: [ValidationWarning]
        public var recommendations: [String]
        
        public var canProceed: Bool {
            // Can proceed if valid or only has warnings
            return isValid || errors.isEmpty
        }
    }
    
    public struct ValidationError: Identifiable {
        public let id = UUID()
        public let entityType: String
        public let entityID: UUID?
        public let field: String?
        public let message: String
        public let severity: Severity
        
        public enum Severity {
            case critical  // Will prevent restore
            case error     // Should prevent restore
            case warning   // Can proceed with caution
        }
    }
    
    public struct ValidationWarning: Identifiable {
        public let id = UUID()
        public let message: String
        public let recommendation: String?
    }
    
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
        
        // Phase 7: Generate recommendations
        recommendations.append(contentsOf: generateRecommendations(payload, errors: errors, warnings: warnings))
        
        let isValid = errors.filter { $0.severity == .critical || $0.severity == .error }.isEmpty
        
        return ValidationResult(
            isValid: isValid,
            errors: errors,
            warnings: warnings,
            recommendations: recommendations
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
    
    // MARK: - Foreign Key Validation
    
    private func validateForeignKeys(_ payload: BackupPayload) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Build ID sets for quick lookup
        let studentIDs = Set(payload.students.map { $0.id })
        let lessonIDs = Set(payload.lessons.map { $0.id })
        let topicIDs = Set(payload.communityTopics.map { $0.id })
        let projectIDs = Set(payload.projects.map { $0.id })
        let roleIDs = Set(payload.projectRoles.map { $0.id })
        let weekIDs = Set(payload.projectTemplateWeeks.map { $0.id })
        
        // Validate StudentLesson references
        for sl in payload.studentLessons {
            // Check lesson reference
            if !lessonIDs.contains(sl.lessonID) {
                errors.append(ValidationError(
                    entityType: "StudentLesson",
                    entityID: sl.id,
                    field: "lessonID",
                    message: "References non-existent lesson: \(sl.lessonID)",
                    severity: .critical
                ))
            }
            
            // Check student references
            for studentID in sl.studentIDs {
                if !studentIDs.contains(studentID) {
                    errors.append(ValidationError(
                        entityType: "StudentLesson",
                        entityID: sl.id,
                        field: "studentIDs",
                        message: "References non-existent student: \(studentID)",
                        severity: .critical
                    ))
                }
            }
        }
        
        // Validate LessonAssignment references
        for assignment in payload.lessonAssignments {
            // Check lesson reference (stored as string UUID)
            if let lessonUUID = UUID(uuidString: assignment.lessonID) {
                if !lessonIDs.contains(lessonUUID) {
                    errors.append(ValidationError(
                        entityType: "LessonAssignment",
                        entityID: assignment.id,
                        field: "lessonID",
                        message: "References non-existent lesson: \(assignment.lessonID)",
                        severity: .critical
                    ))
                }
            } else {
                errors.append(ValidationError(
                    entityType: "LessonAssignment",
                    entityID: assignment.id,
                    field: "lessonID",
                    message: "Invalid lesson ID format: \(assignment.lessonID)",
                    severity: .critical
                ))
            }
            
            // Check student references
            for studentIDString in assignment.studentIDs {
                if let studentUUID = UUID(uuidString: studentIDString) {
                    if !studentIDs.contains(studentUUID) {
                        errors.append(ValidationError(
                            entityType: "LessonAssignment",
                            entityID: assignment.id,
                            field: "studentIDs",
                            message: "References non-existent student: \(studentIDString)",
                            severity: .critical
                        ))
                    }
                }
            }
        }
        
        // Validate AttendanceRecord references
        for record in payload.attendance {
            if !studentIDs.contains(record.studentID) {
                errors.append(ValidationError(
                    entityType: "AttendanceRecord",
                    entityID: record.id,
                    field: "studentID",
                    message: "References non-existent student: \(record.studentID)",
                    severity: .critical
                ))
            }
        }
        
        // Validate ProposedSolution references
        for solution in payload.proposedSolutions {
            if let topicID = solution.topicID, !topicIDs.contains(topicID) {
                errors.append(ValidationError(
                    entityType: "ProposedSolution",
                    entityID: solution.id,
                    field: "topicID",
                    message: "References non-existent community topic: \(topicID)",
                    severity: .critical
                ))
            }
        }
        
        // Validate CommunityAttachment references
        for attachment in payload.communityAttachments {
            if let topicID = attachment.topicID, !topicIDs.contains(topicID) {
                errors.append(ValidationError(
                    entityType: "CommunityAttachment",
                    entityID: attachment.id,
                    field: "topicID",
                    message: "References non-existent community topic: \(topicID)",
                    severity: .critical
                ))
            }
        }
        
        // Validate Project member references
        for project in payload.projects {
            for memberIDString in project.memberStudentIDs {
                if let memberUUID = UUID(uuidString: memberIDString) {
                    if !studentIDs.contains(memberUUID) {
                        errors.append(ValidationError(
                            entityType: "Project",
                            entityID: project.id,
                            field: "memberStudentIDs",
                            message: "References non-existent student: \(memberIDString)",
                            severity: .error
                        ))
                    }
                }
            }
        }
        
        // Validate ProjectRole references
        for role in payload.projectRoles {
            if !projectIDs.contains(role.projectID) {
                errors.append(ValidationError(
                    entityType: "ProjectRole",
                    entityID: role.id,
                    field: "projectID",
                    message: "References non-existent project: \(role.projectID)",
                    severity: .critical
                ))
            }
        }
        
        // Validate ProjectTemplateWeek references
        for week in payload.projectTemplateWeeks {
            if !projectIDs.contains(week.projectID) {
                errors.append(ValidationError(
                    entityType: "ProjectTemplateWeek",
                    entityID: week.id,
                    field: "projectID",
                    message: "References non-existent project: \(week.projectID)",
                    severity: .critical
                ))
            }
        }
        
        // Validate ProjectWeekRoleAssignment references
        for assignment in payload.projectWeekRoleAssignments {
            if !weekIDs.contains(assignment.weekID) {
                errors.append(ValidationError(
                    entityType: "ProjectWeekRoleAssignment",
                    entityID: assignment.id,
                    field: "weekID",
                    message: "References non-existent project week: \(assignment.weekID)",
                    severity: .critical
                ))
            }
            
            if !roleIDs.contains(assignment.roleID) {
                errors.append(ValidationError(
                    entityType: "ProjectWeekRoleAssignment",
                    entityID: assignment.id,
                    field: "roleID",
                    message: "References non-existent project role: \(assignment.roleID)",
                    severity: .critical
                ))
            }
            
            if let studentUUID = UUID(uuidString: assignment.studentID) {
                if !studentIDs.contains(studentUUID) {
                    errors.append(ValidationError(
                        entityType: "ProjectWeekRoleAssignment",
                        entityID: assignment.id,
                        field: "studentID",
                        message: "References non-existent student: \(assignment.studentID)",
                        severity: .critical
                    ))
                }
            }
        }
        
        return errors
    }
    
    // MARK: - Data Constraint Validation
    
    private func validateDataConstraints(_ payload: BackupPayload) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate date constraints
        for sl in payload.studentLessons {
            if let scheduled = sl.scheduledFor, let given = sl.givenAt {
                if given < scheduled {
                    errors.append(ValidationError(
                        entityType: "StudentLesson",
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
        allIDs.append(contentsOf: payload.studentLessons.map { $0.id })
        allIDs.append(contentsOf: payload.lessonAssignments.map { $0.id })
        allIDs.append(contentsOf: payload.workPlanItems.map { $0.id })
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
        if totalEntities > 10000 {
            recommendations.append("Large backup detected (\(totalEntities) entities). Restore may take several minutes.")
        }
        
        return recommendations
    }
}
