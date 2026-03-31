import Foundation
import CoreData
import OSLog

// MARK: - Projects

extension BackupEntityImporter {

    /// Imports projects from DTOs.
    static func importProjects(
        _ dtos: [ProjectDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProject>
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
                return project
            }
        )
    }

    // MARK: - CDProject Roles

    /// Imports project roles from DTOs.
    static func importProjectRoles(
        _ dtos: [ProjectRoleDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProjectRole>
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

    // MARK: - CDProject Template Weeks

    /// Imports project template weeks from DTOs.
    static func importProjectTemplateWeeks(
        _ dtos: [ProjectTemplateWeekDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProjectTemplateWeek>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let week = CDProjectTemplateWeek(context: viewContext)
                week.id = dto.id
                week.createdAt = dto.createdAt
                week.projectID = dto.projectID.uuidString
                week.weekIndex = Int64(dto.weekIndex)
                week.readingRange = dto.readingRange
                week.agendaItemsJSON = dto.agendaItemsJSON
                week.linkedLessonIDsJSON = dto.linkedLessonIDsJSON
                week.workInstructions = dto.workInstructions
                return week
            }
        )
    }

    // MARK: - CDProject Assignment Templates

    /// Imports project assignment templates from DTOs.
    static func importProjectAssignmentTemplates(
        _ dtos: [ProjectAssignmentTemplateDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProjectAssignmentTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let template = CDProjectAssignmentTemplate(context: viewContext)
                template.id = dto.id
                template.createdAt = dto.createdAt
                template.projectID = dto.projectID.uuidString
                template.title = dto.title
                template.instructions = dto.instructions
                template.isShared = dto.isShared
                template.defaultLinkedLessonID = dto.defaultLinkedLessonID
                return template
            }
        )
    }

    // MARK: - CDProject Week Role Assignments

    /// Imports project week role assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project week role assignment DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existingCheck: Function to check if an assignment already exists
    ///   - weekCheck: Function to look up a project template week by ID
    static func importProjectWeekRoleAssignments(
        _ dtos: [ProjectWeekRoleAssignmentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProjectWeekRoleAssignment>,
        weekCheck: EntityExistsCheck<CDProjectTemplateWeek>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing week role assignment: \(desc, privacy: .public)")
                continue
            }

            let assignment = CDProjectWeekRoleAssignment(context: viewContext)
            assignment.id = dto.id
            assignment.createdAt = dto.createdAt
            assignment.weekID = dto.weekID.uuidString
            assignment.studentID = dto.studentID
            assignment.roleID = dto.roleID.uuidString

            do {
                if let week = try weekCheck(dto.weekID) {
                    assignment.week = week
                }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check week for week role assignment: \(desc, privacy: .public)")
            }

            viewContext.insert(assignment)
        }
    }

    // MARK: - CDProject Sessions

    /// Imports project sessions from DTOs.
    static func importProjectSessions(
        _ dtos: [ProjectSessionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProjectSession>
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
                return session
            }
        )
    }
}
