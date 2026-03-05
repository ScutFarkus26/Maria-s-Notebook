import Foundation
import SwiftData

// MARK: - Foreign Key Validation

extension BackupValidationService {

    func validateForeignKeys(_ payload: BackupPayload) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Build ID sets for quick lookup
        let studentIDs = Set(payload.students.map { $0.id })
        let lessonIDs = Set(payload.lessons.map { $0.id })
        let topicIDs = Set(payload.communityTopics.map { $0.id })
        let projectIDs = Set(payload.projects.map { $0.id })
        let roleIDs = Set(payload.projectRoles.map { $0.id })
        let weekIDs = Set(payload.projectTemplateWeeks.map { $0.id })

        // Validate LegacyPresentation references
        for sl in payload.legacyPresentations {
            // Check lesson reference
            if !lessonIDs.contains(sl.lessonID) {
                errors.append(ValidationError(
                    entityType: "LegacyPresentation",
                    entityID: sl.id,
                    field: "lessonID",
                    message: "References non-existent lesson: \(sl.lessonID)",
                    severity: .critical
                ))
            }

            // Check student references
            for studentID in sl.studentIDs where !studentIDs.contains(studentID) {
                errors.append(ValidationError(
                    entityType: "LegacyPresentation",
                    entityID: sl.id,
                    field: "studentIDs",
                    message: "References non-existent student: \(studentID)",
                    severity: .critical
                ))
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
        for record in payload.attendance where !studentIDs.contains(record.studentID) {
            errors.append(ValidationError(
                entityType: "AttendanceRecord",
                entityID: record.id,
                field: "studentID",
                message: "References non-existent student: \(record.studentID)",
                severity: .critical
            ))
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
        for role in payload.projectRoles where !projectIDs.contains(role.projectID) {
            errors.append(ValidationError(
                entityType: "ProjectRole",
                entityID: role.id,
                field: "projectID",
                message: "References non-existent project: \(role.projectID)",
                severity: .critical
            ))
        }

        // Validate ProjectTemplateWeek references
        for week in payload.projectTemplateWeeks where !projectIDs.contains(week.projectID) {
            errors.append(ValidationError(
                entityType: "ProjectTemplateWeek",
                entityID: week.id,
                field: "projectID",
                message: "References non-existent project: \(week.projectID)",
                severity: .critical
            ))
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
}
