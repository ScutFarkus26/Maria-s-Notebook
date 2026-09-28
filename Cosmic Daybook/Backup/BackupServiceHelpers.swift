// BackupServiceHelpers.swift
// Shared utilities for backup services

import Foundation
import CoreData
import OSLog

/// Shared helper utilities for backup operations
enum BackupServiceHelpers {
    private static let logger = Logger.backup

    // MARK: - DTO Conversion

    /// Converts an array of Students to StudentDTOs
    static func toDTOs(_ students: [CDStudent]) -> [StudentDTO] {
        students.compactMap { s in
            guard let sID = s.id else { return nil }
            let level: StudentDTO.Level
            switch s.level {
            case .lower: level = .lower
            case .upper: level = .upper
            case .adolescent: level = .adolescent
            }
            return StudentDTO(
                id: sID,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday,
                dateStarted: s.dateStarted,
                level: level,
                nextLessons: s.nextLessonUUIDs,
                manualOrder: Int(s.manualOrder),
                createdAt: nil,
                updatedAt: nil,
                nickname: s.nickname,
                enrollmentStatusRaw: s.enrollmentStatusRaw,
                dateWithdrawn: s.dateWithdrawn,
                modifiedAt: s.modifiedAt,
                previousLevelRaw: s.previousLevelRaw,
                dateLastPromoted: s.dateLastPromoted
            )
        }
    }

    /// Converts an array of Lessons to LessonDTOs
    static func toDTOs(_ lessons: [CDLesson]) -> [LessonDTO] {
        lessons.compactMap { l in
            guard let lID = l.id else { return nil }
            return LessonDTO(
                id: lID,
                name: l.name,
                area: l.area,
                sequence: l.sequence,
                orderInSequence: Int(l.orderInSequence),
                section: l.section,
                writeUp: l.writeUp,
                createdAt: nil,
                updatedAt: nil,
                pagesFileRelativePath: l.pagesFileRelativePath,
                primaryAttachmentID: l.primaryAttachmentIDUUID,
                // Montessori album fields (format v9+) — must be backed up or teacher-authored
                // album content is silently dropped on every export and lost on restore.
                suggestedFollowUpWork: l.suggestedFollowUpWork,
                sourceRaw: l.sourceRaw,
                personalKindRaw: l.personalKindRaw,
                defaultWorkKindRaw: l.defaultWorkKindRaw,
                materials: l.materials,
                purpose: l.purpose,
                ageRange: l.ageRange,
                teacherNotes: l.teacherNotes,
                prerequisiteLessonIDs: l.prerequisiteLessonIDs,
                relatedLessonIDs: l.relatedLessonIDs,
                parshaKey: l.parshaKey,
                greatLessonRaw: l.greatLessonRaw,
                lessonFormatRaw: l.lessonFormatRaw,
                sortIndex: Int(l.sortIndex),
                derivedFromLessonID: l.derivedFromLessonID,
                parentStoryID: l.parentStoryID,
                requiresPracticeOverride: l.requiresPracticeOverride,
                requiresConfirmationOverride: l.requiresConfirmationOverride,
                // Teaching-album link — the guide's own matching work, not
                // recoverable from the PDFs after a restore.
                albumID: l.albumID,
                albumPageIndex: Int(l.albumPageIndex),
                albumLessonTitle: l.albumLessonTitle,
                albumLinkConfidence: l.albumLinkConfidence,
                // Three-Year View milestone flag — hand-marked by the guide.
                isKeyLesson: l.isKeyLesson
            )
        }
    }

    /// Converts an array of Notes to NoteDTOs
    static func toDTOs(_ notes: [CDNote]) -> [NoteDTO] {
        notes.compactMap { n in
            guard let nID = n.id else { return nil }
            let scopeString: String
            do {
                let data = try JSONEncoder().encode(n.scope)
                scopeString = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                logger.warning("Failed to encode note scope: \(error.localizedDescription, privacy: .public)")
                scopeString = "{}"
            }
            let tagsArray = (n.tags as? [String]) ?? []
            return NoteDTO(
                id: nID,
                createdAt: n.createdAt ?? Date(),
                updatedAt: n.updatedAt ?? Date(),
                body: n.body,
                isPinned: n.isPinned,
                scope: scopeString,
                tags: tagsArray.isEmpty ? nil : tagsArray,
                needsFollowUp: n.needsFollowUp ? true : nil,
                // Read the string FK directly: `n.lesson` is a computed cross-store
                // accessor that fetches the lesson and returns nil when it can't be
                // resolved — which would silently drop the link from the backup.
                lessonID: n.lessonID.flatMap { UUID(uuidString: $0) },
                workID: n.work?.id,
                imagePath: n.imagePath,
                includeInReport: n.includeInReport,
                reportedBy: n.reportedBy,
                reporterName: n.reporterName,
                communityTopicID: n.communityTopicID,
                schoolDayOverrideID: n.schoolDayOverrideID,
                studentTrackEnrollmentID: n.studentTrackEnrollmentID,
                goingOutID: n.goingOutID,
                lessonAssignmentID: n.lessonAssignment?.id,
                attendanceRecordID: n.attendanceRecordID.flatMap { UUID(uuidString: $0) },
                workCheckInID: n.workCheckIn?.id,
                workCompletionRecordID: n.workCompletionRecord?.id,
                studentMeetingID: n.studentMeeting?.id,
                projectSessionID: n.projectSession?.id,
                reminderID: n.reminder?.id,
                practiceSessionID: n.practiceSession?.id,
                issueID: n.issue?.id
            )
        }
    }

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
                absenceReason: a.absenceReason.rawValue == "none" ? nil : a.absenceReason.rawValue,
                recordedBy: a.recordedBy,
                recordedByID: a.recordedByID,
                recordedByName: a.recordedByName,
                modifiedAt: a.modifiedAt,
                note: a.note
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
