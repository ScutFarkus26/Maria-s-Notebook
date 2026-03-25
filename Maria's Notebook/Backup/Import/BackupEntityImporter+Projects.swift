import Foundation
import SwiftData
import OSLog

// MARK: - Projects

extension BackupEntityImporter {

    /// Imports projects from DTOs.
    static func importProjects(
        _ dtos: [ProjectDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Project>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                Project(
                    id: dto.id, createdAt: dto.createdAt,
                    title: dto.title, bookTitle: dto.bookTitle,
                    memberStudentIDs: dto.memberStudentIDs
                )
            }
        )
    }

    // MARK: - Project Roles

    /// Imports project roles from DTOs.
    static func importProjectRoles(
        _ dtos: [ProjectRoleDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectRole>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                ProjectRole(
                    id: dto.id, createdAt: dto.createdAt,
                    projectID: dto.projectID,
                    title: dto.title, summary: dto.summary,
                    instructions: dto.instructions
                )
            }
        )
    }

    // MARK: - Project Template Weeks

    /// Imports project template weeks from DTOs.
    static func importProjectTemplateWeeks(
        _ dtos: [ProjectTemplateWeekDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectTemplateWeek>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                ProjectTemplateWeek(
                    id: dto.id, createdAt: dto.createdAt,
                    projectID: dto.projectID,
                    weekIndex: dto.weekIndex,
                    readingRange: dto.readingRange,
                    agendaItemsJSON: dto.agendaItemsJSON,
                    linkedLessonIDsJSON: dto.linkedLessonIDsJSON,
                    workInstructions: dto.workInstructions
                )
            }
        )
    }

    // MARK: - Project Assignment Templates

    /// Imports project assignment templates from DTOs.
    static func importProjectAssignmentTemplates(
        _ dtos: [ProjectAssignmentTemplateDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectAssignmentTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                ProjectAssignmentTemplate(
                    id: dto.id, createdAt: dto.createdAt,
                    projectID: dto.projectID,
                    title: dto.title,
                    instructions: dto.instructions,
                    isShared: dto.isShared,
                    defaultLinkedLessonID: dto.defaultLinkedLessonID
                )
            }
        )
    }

    // MARK: - Project Week Role Assignments

    /// Imports project week role assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project week role assignment DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if an assignment already exists
    ///   - weekCheck: Function to look up a project template week by ID
    static func importProjectWeekRoleAssignments(
        _ dtos: [ProjectWeekRoleAssignmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectWeekRoleAssignment>,
        weekCheck: EntityExistsCheck<ProjectTemplateWeek>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing week role assignment: \(desc, privacy: .public)")
                continue
            }

            let assignment = ProjectWeekRoleAssignment(
                id: dto.id,
                createdAt: dto.createdAt,
                weekID: dto.weekID,
                studentID: dto.studentID,
                roleID: dto.roleID,
                week: nil
            )

            do {
                if let week = try weekCheck(dto.weekID) {
                    assignment.week = week
                }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check week for week role assignment: \(desc, privacy: .public)")
            }

            modelContext.insert(assignment)
        }
    }

    // MARK: - Project Sessions

    /// Imports project sessions from DTOs.
    static func importProjectSessions(
        _ dtos: [ProjectSessionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectSession>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                ProjectSession(
                    id: dto.id, createdAt: dto.createdAt,
                    projectID: dto.projectID,
                    meetingDate: dto.meetingDate,
                    chapterOrPages: dto.chapterOrPages,
                    agendaItemsJSON: dto.agendaItemsJSON,
                    templateWeekID: dto.templateWeekID
                )
            }
        )
    }
}
