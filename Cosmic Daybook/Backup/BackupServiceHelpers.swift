// BackupServiceHelpers.swift
// Shared utilities for backup services

import Foundation
import CoreData

/// Shared helper utilities for backup operations
enum BackupServiceHelpers {

    // MARK: - DTO Conversion

    /// Converts an array of AttendanceRecords to AttendanceRecordDTOs
    static func toDTOs(_ attendance: [CDAttendanceRecord]) -> [AttendanceRecordDTO] {
        attendance.compactMap { a in
            guard let aID = a.id,
                  let aDate = a.date,
                  let studentIDUUID = UUID(uuidString: a.studentID) else { return nil }
            return AttendanceRecordDTO(
                id: aID,
                studentID: studentIDUUID,
                date: aDate,
                status: a.status.rawValue,
                // As stored: the typed reason has no case for Close Arrival's
                // "closeArrival", which it read as none and the backup dropped.
                absenceReason: a.absenceReasonRaw == AbsenceReason.none.rawValue ? nil : a.absenceReasonRaw,
                recordedBy: a.recordedBy,
                recordedByID: a.recordedByID,
                recordedByName: a.recordedByName,
                modifiedAt: a.modifiedAt,
                note: a.note,
                markedAt: a.markedAt,
                leftAt: a.leftAt,
                leavesAt: a.leavesAt,
                returnedAt: a.returnedAt,
                statusBeforeLeavingRaw: a.statusBeforeLeavingRaw
            )
        }
    }

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

    // MARK: - Simple DTO Conversions

    static func toDTOs(_ nonSchoolDays: [CDNonSchoolDay]) -> [NonSchoolDayDTO] {
        nonSchoolDays.compactMap { nsd in
            guard let nsdID = nsd.id, let nsdDate = nsd.date else { return nil }
            return NonSchoolDayDTO(id: nsdID, date: nsdDate, reason: nsd.reason)
        }
    }

    static func toDTOs(_ schoolDayOverrides: [CDSchoolDayOverride]) -> [SchoolDayOverrideDTO] {
        schoolDayOverrides.compactMap { ovr in
            guard let ovrID = ovr.id, let ovrDate = ovr.date else { return nil }
            return SchoolDayOverrideDTO(id: ovrID, date: ovrDate)
        }
    }

    static func toDTOs(_ studentMeetings: [CDStudentMeeting]) -> [StudentMeetingDTO] {
        studentMeetings.compactMap { m in
            guard let mID = m.id,
                  let mDate = m.date,
                  let studentIDUUID = UUID(uuidString: m.studentID) else { return nil }
            return StudentMeetingDTO(
                id: mID,
                studentID: studentIDUUID,
                date: mDate,
                completed: m.completed,
                reflection: m.reflection,
                focus: m.focus,
                requests: m.requests,
                guideNotes: m.guideNotes
            )
        }
    }

    static func toDTOs(_ communityTopics: [CDCommunityTopicEntity]) -> [CommunityTopicDTO] {
        communityTopics.compactMap { t in
            guard let tID = t.id else { return nil }
            return CommunityTopicDTO(
                id: tID,
                title: t.title,
                issueDescription: t.issueDescription,
                createdAt: t.createdAt ?? Date(),
                addressedDate: t.addressedDate,
                resolution: t.resolution,
                raisedBy: t.raisedBy,
                tags: t.tags
            )
        }
    }

    static func toDTOs(_ communityAttachments: [CDCommunityAttachment]) -> [CommunityAttachmentDTO] {
        communityAttachments.compactMap { a in
            guard let aID = a.id else { return nil }
            return CommunityAttachmentDTO(
                id: aID,
                topicID: a.topic?.id,
                filename: a.filename,
                kind: a.kind.rawValue,
                createdAt: a.createdAt ?? Date()
            )
        }
    }

}
