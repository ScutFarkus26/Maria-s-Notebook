import Foundation
import CoreData
import OSLog

// MARK: - Projects

extension BackupEntityImporter {

    /// Imports projects from DTOs.
    static func importProjects(
        _ dtos: [ProjectDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let project = CDProject(context: viewContext)
                project.id = dto.id
                project.createdAt = dto.createdAt
                project.title = dto.title
                project.bookTitle = dto.bookTitle
                project.memberStudentIDsArray = dto.memberStudentIDs
                project.isActive = dto.isActive ?? true
                // Preserve the original modification time (awakeFromInsert stamped
                // "now"); older backups lack the field and keep the import-time stamp.
                if let v = dto.modifiedAt { project.modifiedAt = v }
                return project
            }
        )
    }

    // MARK: - CDProject Roles

    /// Imports project roles from DTOs.
    static func importProjectRoles(
        _ dtos: [ProjectRoleDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let role = CDProjectRole(context: viewContext)
                role.id = dto.id
                role.createdAt = dto.createdAt
                role.projectID = dto.projectID.uuidString
                role.title = dto.title
                role.summary = dto.summary
                role.instructions = dto.instructions
                return role
            }
        )
    }

    // Import methods for CDProjectTemplateWeek, CDProjectAssignmentTemplate,
    // and CDProjectWeekRoleAssignment removed — entities deprecated.

    // MARK: - CDProject Sessions

    /// Imports project sessions from DTOs.
    static func importProjectSessions(
        _ dtos: [ProjectSessionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let session = CDProjectSession(context: viewContext)
                session.id = dto.id
                session.createdAt = dto.createdAt
                session.projectID = dto.projectID.uuidString
                session.meetingDate = dto.meetingDate
                session.chapterOrPages = dto.chapterOrPages
                session.agendaItemsJSON = dto.agendaItemsJSON
                session.templateWeekID = dto.templateWeekID?.uuidString
                if let v = dto.assignmentModeRaw { session.assignmentModeRaw = v }
                if let v = dto.minSelections { session.minSelections = Int64(v) }
                if let v = dto.maxSelections { session.maxSelections = Int64(v) }
                return session
            }
        )
    }
}
