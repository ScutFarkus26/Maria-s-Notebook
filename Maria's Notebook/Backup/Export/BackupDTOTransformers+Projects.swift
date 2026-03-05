import Foundation
import SwiftData

// MARK: - Project Transformers (Project, ProjectSession, ProjectRole, ProjectTemplateWeek,
//         ProjectWeekRoleAssignment, CommunityTopic, ProposedSolution, CommunityAttachment)

extension BackupDTOTransformers {

    // MARK: - Project

    static func toDTO(_ project: Project) -> ProjectDTO {
        ProjectDTO(
            id: project.id,
            createdAt: project.createdAt,
            title: project.title,
            bookTitle: project.bookTitle,
            memberStudentIDs: project.memberStudentIDs
        )
    }

    // MARK: - ProjectAssignmentTemplate

    static func toDTO(_ template: ProjectAssignmentTemplate) -> ProjectAssignmentTemplateDTO? {
        guard let projectIDUUID = UUID(uuidString: template.projectID) else { return nil }
        return ProjectAssignmentTemplateDTO(
            id: template.id,
            createdAt: template.createdAt,
            projectID: projectIDUUID,
            title: template.title,
            instructions: template.instructions,
            isShared: template.isShared,
            defaultLinkedLessonID: template.defaultLinkedLessonID
        )
    }

    // MARK: - ProjectSession

    static func toDTO(_ session: ProjectSession) -> ProjectSessionDTO? {
        guard let projectIDUUID = UUID(uuidString: session.projectID) else { return nil }
        let templateWeekIDUUID = session.templateWeekID.flatMap { UUID(uuidString: $0) }
        return ProjectSessionDTO(
            id: session.id,
            createdAt: session.createdAt,
            projectID: projectIDUUID,
            meetingDate: session.meetingDate,
            chapterOrPages: session.chapterOrPages,
            agendaItemsJSON: session.agendaItemsJSON,
            templateWeekID: templateWeekIDUUID
        )
    }

    // MARK: - ProjectRole

    static func toDTO(_ role: ProjectRole) -> ProjectRoleDTO? {
        guard let projectIDUUID = UUID(uuidString: role.projectID) else { return nil }
        return ProjectRoleDTO(
            id: role.id,
            createdAt: role.createdAt,
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
            id: week.id,
            createdAt: week.createdAt,
            projectID: projectIDUUID,
            weekIndex: week.weekIndex,
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
            id: assignment.id,
            createdAt: assignment.createdAt,
            weekID: weekIDUUID,
            studentID: assignment.studentID,
            roleID: roleIDUUID
        )
    }

    // MARK: - CommunityTopic

    static func toDTO(_ topic: CommunityTopic) -> CommunityTopicDTO {
        CommunityTopicDTO(
            id: topic.id,
            title: topic.title,
            issueDescription: topic.issueDescription,
            createdAt: topic.createdAt,
            addressedDate: topic.addressedDate,
            resolution: topic.resolution,
            raisedBy: topic.raisedBy,
            tags: topic.tags
        )
    }

    // MARK: - ProposedSolution

    static func toDTO(_ solution: ProposedSolution) -> ProposedSolutionDTO {
        ProposedSolutionDTO(
            id: solution.id,
            topicID: solution.topic?.id,
            title: solution.title,
            details: solution.details,
            proposedBy: solution.proposedBy,
            createdAt: solution.createdAt,
            isAdopted: solution.isAdopted
        )
    }

    // MARK: - CommunityAttachment

    static func toDTO(_ attachment: CommunityAttachment) -> CommunityAttachmentDTO {
        CommunityAttachmentDTO(
            id: attachment.id,
            topicID: attachment.topic?.id,
            filename: attachment.filename,
            kind: attachment.kind.rawValue,
            createdAt: attachment.createdAt
        )
    }

    // MARK: - Batch Transformations (Projects)

    static func toDTOs(_ projects: [Project]) -> [ProjectDTO] {
        projects.map { toDTO($0) }
    }

    static func toDTOs(_ templates: [ProjectAssignmentTemplate]) -> [ProjectAssignmentTemplateDTO] {
        templates.compactMap { toDTO($0) }
    }

    static func toDTOs(_ sessions: [ProjectSession]) -> [ProjectSessionDTO] {
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

    static func toDTOs(_ topics: [CommunityTopic]) -> [CommunityTopicDTO] {
        topics.map { toDTO($0) }
    }

    static func toDTOs(_ solutions: [ProposedSolution]) -> [ProposedSolutionDTO] {
        solutions.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [CommunityAttachment]) -> [CommunityAttachmentDTO] {
        attachments.map { toDTO($0) }
    }
}
