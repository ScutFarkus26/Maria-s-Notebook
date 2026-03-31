import Foundation
import CoreData

// MARK: - CDProject Transformers (CDProject, CDProjectSession, ProjectRole, ProjectTemplateWeek,
//         ProjectWeekRoleAssignment, CDCommunityTopicEntity, ProposedSolution, CommunityAttachment)

extension BackupDTOTransformers {

    // MARK: - CDProject

    static func toDTO(_ project: CDProject) -> ProjectDTO {
        ProjectDTO(
            id: project.id ?? UUID(),
            createdAt: project.createdAt ?? Date(),
            title: project.title,
            bookTitle: project.bookTitle,
            memberStudentIDs: (project.memberStudentIDs as? [String]) ?? []
        )
    }

    // MARK: - ProjectAssignmentTemplate

    static func toDTO(_ template: ProjectAssignmentTemplate) -> ProjectAssignmentTemplateDTO? {
        guard let projectIDUUID = UUID(uuidString: template.projectID) else { return nil }
        return ProjectAssignmentTemplateDTO(
            id: template.id ?? UUID(),
            createdAt: template.createdAt ?? Date(),
            projectID: projectIDUUID,
            title: template.title,
            instructions: template.instructions,
            isShared: template.isShared,
            defaultLinkedLessonID: template.defaultLinkedLessonID
        )
    }

    // MARK: - CDProjectSession

    static func toDTO(_ session: CDProjectSession) -> ProjectSessionDTO? {
        guard let projectIDUUID = UUID(uuidString: session.projectID) else { return nil }
        let templateWeekIDUUID = session.templateWeekID.flatMap { UUID(uuidString: $0) }
        return ProjectSessionDTO(
            id: session.id ?? UUID(),
            createdAt: session.createdAt ?? Date(),
            projectID: projectIDUUID,
            meetingDate: session.meetingDate ?? Date(),
            chapterOrPages: session.chapterOrPages,
            agendaItemsJSON: session.agendaItemsJSON,
            templateWeekID: templateWeekIDUUID
        )
    }

    // MARK: - ProjectRole

    static func toDTO(_ role: ProjectRole) -> ProjectRoleDTO? {
        guard let projectIDUUID = UUID(uuidString: role.projectID) else { return nil }
        return ProjectRoleDTO(
            id: role.id ?? UUID(),
            createdAt: role.createdAt ?? Date(),
            projectID: projectIDUUID,
            title: role.title,
            summary: role.summary,
            instructions: role.instructions
        )
    }

    // MARK: - ProjectTemplateWeek

    static func toDTO(_ week: ProjectTemplateWeek) -> ProjectTemplateWeekDTO? {
        guard let projectIDUUID = UUID(uuidString: week.projectID) else { return nil }
        return ProjectTemplateWeekDTO(
            id: week.id ?? UUID(),
            createdAt: week.createdAt ?? Date(),
            projectID: projectIDUUID,
            weekIndex: Int(week.weekIndex),
            readingRange: week.readingRange,
            agendaItemsJSON: week.agendaItemsJSON,
            linkedLessonIDsJSON: week.linkedLessonIDsJSON,
            workInstructions: week.workInstructions
        )
    }

    // MARK: - ProjectWeekRoleAssignment

    static func toDTO(_ assignment: ProjectWeekRoleAssignment) -> ProjectWeekRoleAssignmentDTO? {
        guard let weekIDUUID = UUID(uuidString: assignment.weekID),
              let roleIDUUID = UUID(uuidString: assignment.roleID) else { return nil }
        return ProjectWeekRoleAssignmentDTO(
            id: assignment.id ?? UUID(),
            createdAt: assignment.createdAt ?? Date(),
            weekID: weekIDUUID,
            studentID: assignment.studentID,
            roleID: roleIDUUID
        )
    }

    // MARK: - CDCommunityTopicEntity

    static func toDTO(_ topic: CDCommunityTopicEntity) -> CommunityTopicDTO {
        CommunityTopicDTO(
            id: topic.id ?? UUID(),
            title: topic.title,
            issueDescription: topic.issueDescription,
            createdAt: topic.createdAt ?? Date(),
            addressedDate: topic.addressedDate,
            resolution: topic.resolution,
            raisedBy: topic.raisedBy,
            tags: topic.tags
        )
    }

    // MARK: - ProposedSolution

    static func toDTO(_ solution: ProposedSolution) -> ProposedSolutionDTO {
        ProposedSolutionDTO(
            id: solution.id ?? UUID(),
            topicID: solution.topic?.id,
            title: solution.title,
            details: solution.details,
            proposedBy: solution.proposedBy,
            createdAt: solution.createdAt ?? Date(),
            isAdopted: solution.isAdopted
        )
    }

    // MARK: - CommunityAttachment

    static func toDTO(_ attachment: CommunityAttachment) -> CommunityAttachmentDTO {
        CommunityAttachmentDTO(
            id: attachment.id ?? UUID(),
            topicID: attachment.topic?.id,
            filename: attachment.filename,
            kind: attachment.kind.rawValue,
            createdAt: attachment.createdAt ?? Date()
        )
    }

    // MARK: - Batch Transformations (Projects)

    static func toDTOs(_ projects: [CDProject]) -> [ProjectDTO] {
        projects.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [ProjectAssignmentTemplate]) -> [ProjectAssignmentTemplateDTO] {
        templates.compactMap { toDTO($0) }
    }

    static func toDTOs(_ sessions: [CDProjectSession]) -> [ProjectSessionDTO] {
        sessions.compactMap { toDTO($0) }
    }

    static func toDTOs(_ roles: [ProjectRole]) -> [ProjectRoleDTO] {
        roles.compactMap { toDTO($0) }
    }

    static func toDTOs(_ weeks: [ProjectTemplateWeek]) -> [ProjectTemplateWeekDTO] {
        weeks.compactMap { toDTO($0) }
    }

    static func toDTOs(_ assignments: [ProjectWeekRoleAssignment]) -> [ProjectWeekRoleAssignmentDTO] {
        assignments.compactMap { toDTO($0) }
    }

    static func toDTOs(_ topics: [CDCommunityTopicEntity]) -> [CommunityTopicDTO] {
        topics.map { toDTO($0) }
    }

    static func toDTOs(_ solutions: [ProposedSolution]) -> [ProposedSolutionDTO] {
        solutions.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [CommunityAttachment]) -> [CommunityAttachmentDTO] {
        attachments.map { toDTO($0) }
    }
}
