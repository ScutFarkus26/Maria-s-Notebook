// BackupServiceHelpers.swift
// Shared utilities for backup services

import Foundation
import CoreData

/// Shared helper utilities for backup operations
enum BackupServiceHelpers {

    // MARK: - DTO Conversion

    /// Converts an array of WorkCompletionRecords to WorkCompletionRecordDTOs
    static func toDTOs(_ workCompletions: [CDWorkCompletionRecord]) -> [WorkCompletionRecordDTO] {
        workCompletions.compactMap { r in
            guard let rID = r.id,
                  let rCompletedAt = r.completedAt,
                  let workIDUUID = UUID(uuidString: r.workID),
                  let studentIDUUID = UUID(uuidString: r.studentID) else { return nil }
            return WorkCompletionRecordDTO(
                id: rID,
                workID: workIDUUID,
                studentID: studentIDUUID,
                completedAt: rCompletedAt
            )
        }
    }

    /// Converts an array of Projects to ProjectDTOs
    static func toDTOs(_ projects: [CDProject]) -> [ProjectDTO] {
        projects.compactMap { c in
            guard let cID = c.id else { return nil }
            return ProjectDTO(
                id: cID,
                createdAt: c.createdAt ?? Date(),
                title: c.title,
                bookTitle: c.bookTitle,
                memberStudentIDs: c.memberStudentIDsArray,
                isActive: c.isActive,
                modifiedAt: c.modifiedAt
            )
        }
    }

    /// Converts an array of ProjectSessions to ProjectSessionDTOs
    static func toDTOs(_ projectSessions: [CDProjectSession]) -> [ProjectSessionDTO] {
        projectSessions.compactMap { s in
            guard let sID = s.id,
                  let sMeetingDate = s.meetingDate,
                  let projectIDUUID = UUID(uuidString: s.projectID) else { return nil }
            let templateWeekIDUUID = s.templateWeekID.flatMap { UUID(uuidString: $0) }
            return ProjectSessionDTO(
                id: sID,
                createdAt: s.createdAt ?? Date(),
                projectID: projectIDUUID,
                meetingDate: sMeetingDate,
                chapterOrPages: s.chapterOrPages,
                agendaItemsJSON: s.agendaItemsJSON,
                templateWeekID: templateWeekIDUUID,
                assignmentModeRaw: s.assignmentModeRaw,
                minSelections: Int(s.minSelections),
                maxSelections: Int(s.maxSelections)
            )
        }
    }

    /// Converts an array of ProjectRoles to ProjectRoleDTOs
    static func toDTOs(_ projectRoles: [CDProjectRole]) -> [ProjectRoleDTO] {
        projectRoles.compactMap { r in
            guard let rID = r.id,
                  let projectIDUUID = UUID(uuidString: r.projectID) else { return nil }
            return ProjectRoleDTO(
                id: rID,
                createdAt: r.createdAt ?? Date(),
                projectID: projectIDUUID,
                title: r.title,
                summary: r.summary,
                instructions: r.instructions
            )
        }
    }
}
