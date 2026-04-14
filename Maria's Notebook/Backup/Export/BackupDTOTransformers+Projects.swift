import Foundation
import CoreData

// MARK: - CDProject Transformers (CDProject, CDProjectSession, CDProjectRole,
//         CDCommunityTopicEntity, CDProposedSolutionEntity, CDCommunityAttachmentEntity)

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

    // MARK: - CDProjectRole

    static func toDTO(_ role: CDProjectRole) -> ProjectRoleDTO? {
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

    // MARK: - CDProposedSolutionEntity

    static func toDTO(_ solution: CDProposedSolutionEntity) -> ProposedSolutionDTO {
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

    // MARK: - CDCommunityAttachmentEntity

    static func toDTO(_ attachment: CDCommunityAttachmentEntity) -> CommunityAttachmentDTO {
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

    static func toDTOs(_ sessions: [CDProjectSession]) -> [ProjectSessionDTO] {
        sessions.compactMap { toDTO($0) }
    }

    static func toDTOs(_ roles: [CDProjectRole]) -> [ProjectRoleDTO] {
        roles.compactMap { toDTO($0) }
    }

    static func toDTOs(_ topics: [CDCommunityTopicEntity]) -> [CommunityTopicDTO] {
        topics.map { toDTO($0) }
    }

    static func toDTOs(_ solutions: [CDProposedSolutionEntity]) -> [ProposedSolutionDTO] {
        solutions.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [CDCommunityAttachmentEntity]) -> [CommunityAttachmentDTO] {
        attachments.map { toDTO($0) }
    }
}
