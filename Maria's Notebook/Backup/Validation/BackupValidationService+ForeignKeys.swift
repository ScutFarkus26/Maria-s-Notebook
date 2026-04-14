import Foundation
import CoreData

// MARK: - Foreign Key Validation

extension BackupValidationService {

    func validateForeignKeys(_ payload: BackupPayload) -> [ValidationError] {
        // Build ID sets for quick lookup
        let studentIDs = Set(payload.students.map(\.id))
        let lessonIDs = Set(payload.lessons.map(\.id))
        let topicIDs = Set(payload.communityTopics.map(\.id))
        let projectIDs = Set(payload.projects.map(\.id))
        let roleIDs = Set(payload.projectRoles.map(\.id))
        let weekIDs = Set(payload.projectTemplateWeeks.map(\.id))

        var errors: [ValidationError] = []
        errors += validateLessonAssignmentRefs(payload, studentIDs: studentIDs, lessonIDs: lessonIDs)
        errors += validateAttendanceRefs(payload, studentIDs: studentIDs)
        errors += validateCommunityRefs(payload, topicIDs: topicIDs)
        errors += validateProjectRefs(
            payload, studentIDs: studentIDs, projectIDs: projectIDs,
            roleIDs: roleIDs, weekIDs: weekIDs
        )
        return errors
    }

    // MARK: - Validation Helpers

    private func validateLessonAssignmentRefs(
        _ payload: BackupPayload,
        studentIDs: Set<UUID>,
        lessonIDs: Set<UUID>
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        for assignment in payload.lessonAssignments {
            if let lessonUUID = UUID(uuidString: assignment.lessonID) {
                if !lessonIDs.contains(lessonUUID) {
                    errors.append(ValidationError(
                        entityType: "LessonAssignment", entityID: assignment.id, field: "lessonID",
                        message: "References non-existent lesson: \(assignment.lessonID)", severity: .critical
                    ))
                }
            } else {
                errors.append(ValidationError(
                    entityType: "LessonAssignment", entityID: assignment.id, field: "lessonID",
                    message: "Invalid lesson ID format: \(assignment.lessonID)", severity: .critical
                ))
            }
            for studentIDString in assignment.studentIDs {
                if let studentUUID = UUID(uuidString: studentIDString) {
                    if !studentIDs.contains(studentUUID) {
                        errors.append(ValidationError(
                            entityType: "LessonAssignment", entityID: assignment.id, field: "studentIDs",
                            message: "References non-existent student: \(studentIDString)", severity: .critical
                        ))
                    }
                }
            }
        }
        return errors
    }

    private func validateAttendanceRefs(
        _ payload: BackupPayload,
        studentIDs: Set<UUID>
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        for record in payload.attendance where !studentIDs.contains(record.studentID) {
            errors.append(ValidationError(
                entityType: "AttendanceRecord", entityID: record.id, field: "studentID",
                message: "References non-existent student: \(record.studentID)", severity: .critical
            ))
        }
        return errors
    }

    private func validateCommunityRefs(
        _ payload: BackupPayload,
        topicIDs: Set<UUID>
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        for solution in payload.proposedSolutions {
            if let topicID = solution.topicID, !topicIDs.contains(topicID) {
                errors.append(ValidationError(
                    entityType: "ProposedSolution", entityID: solution.id, field: "topicID",
                    message: "References non-existent community topic: \(topicID)", severity: .critical
                ))
            }
        }
        for attachment in payload.communityAttachments {
            if let topicID = attachment.topicID, !topicIDs.contains(topicID) {
                errors.append(ValidationError(
                    entityType: "CommunityAttachment", entityID: attachment.id, field: "topicID",
                    message: "References non-existent community topic: \(topicID)", severity: .critical
                ))
            }
        }
        return errors
    }

    private func validateProjectRefs(
        _ payload: BackupPayload,
        studentIDs: Set<UUID>,
        projectIDs: Set<UUID>,
        roleIDs: Set<UUID>,
        weekIDs: Set<UUID>
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        for project in payload.projects {
            for memberIDString in project.memberStudentIDs {
                if let memberUUID = UUID(uuidString: memberIDString), !studentIDs.contains(memberUUID) {
                    errors.append(ValidationError(
                        entityType: "Project", entityID: project.id, field: "memberStudentIDs",
                        message: "References non-existent student: \(memberIDString)", severity: .error
                    ))
                }
            }
        }
        for role in payload.projectRoles where !projectIDs.contains(role.projectID) {
            errors.append(ValidationError(
                entityType: "ProjectRole", entityID: role.id, field: "projectID",
                message: "References non-existent project: \(role.projectID)", severity: .critical
            ))
        }
        // ProjectTemplateWeek and ProjectWeekRoleAssignment validation removed — deprecated
        return errors
    }
}
