// BackupServiceHelpers.swift
// Shared utilities for backup services

import Foundation
import SwiftData

/// Shared helper utilities for backup operations
@MainActor
enum BackupServiceHelpers {

    // MARK: - DTO Conversion

    /// Converts an array of Students to StudentDTOs
    static func toDTOs(_ students: [Student]) -> [StudentDTO] {
        students.map { s in
            let level: StudentDTO.Level = (s.level == .upper) ? .upper : .lower
            return StudentDTO(
                id: s.id,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday,
                dateStarted: s.dateStarted,
                level: level,
                nextLessons: s.nextLessonUUIDs,
                manualOrder: s.manualOrder,
                createdAt: nil,
                updatedAt: nil
            )
        }
    }

    /// Converts an array of Lessons to LessonDTOs
    static func toDTOs(_ lessons: [Lesson]) -> [LessonDTO] {
        lessons.map { l in
            LessonDTO(
                id: l.id,
                name: l.name,
                subject: l.subject,
                group: l.group,
                orderInGroup: l.orderInGroup,
                subheading: l.subheading,
                writeUp: l.writeUp,
                createdAt: nil,
                updatedAt: nil,
                pagesFileRelativePath: l.pagesFileRelativePath
            )
        }
    }

    /// Converts an array of StudentLessons to StudentLessonDTOs
    static func toDTOs(_ studentLessons: [StudentLesson]) -> [StudentLessonDTO] {
        studentLessons.compactMap { sl in
            guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { return nil }
            return StudentLessonDTO(
                id: sl.id,
                lessonID: lessonIDUUID,
                studentIDs: sl.resolvedStudentIDs,
                createdAt: sl.createdAt,
                scheduledFor: sl.scheduledFor,
                givenAt: sl.givenAt,
                isPresented: sl.isPresented,
                notes: sl.notes,
                needsPractice: sl.needsPractice,
                needsAnotherPresentation: sl.needsAnotherPresentation,
                followUpWork: sl.followUpWork,
                studentGroupKey: nil
            )
        }
    }

    /// Converts an array of Notes to NoteDTOs
    static func toDTOs(_ notes: [Note]) -> [NoteDTO] {
        notes.map { n in
            let scopeString: String
            do {
                let data = try JSONEncoder().encode(n.scope)
                scopeString = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                print("⚠️ [Backup:toDTOs] Failed to encode note scope: \(error)")
                scopeString = "{}"
            }
            return NoteDTO(
                id: n.id,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                body: n.body,
                isPinned: n.isPinned,
                scope: scopeString,
                lessonID: n.lesson?.id,
                imagePath: n.imagePath
            )
        }
    }

    /// WorkPlanItem removed in Phase 6 - no longer backed up
    /// Old backups with WorkPlanItems are converted to WorkCheckIns on import

    /// Converts an array of AttendanceRecords to AttendanceRecordDTOs
    static func toDTOs(_ attendance: [AttendanceRecord]) -> [AttendanceRecordDTO] {
        attendance.compactMap { a in
            guard let studentIDUUID = UUID(uuidString: a.studentID) else { return nil }
            return AttendanceRecordDTO(
                id: a.id,
                studentID: studentIDUUID,
                date: a.date,
                status: a.status.rawValue,
                absenceReason: a.absenceReason.rawValue == "none" ? nil : a.absenceReason.rawValue
            )
        }
    }

    /// Converts an array of WorkCompletionRecords to WorkCompletionRecordDTOs
    static func toDTOs(_ workCompletions: [WorkCompletionRecord]) -> [WorkCompletionRecordDTO] {
        workCompletions.compactMap { r in
            guard let workIDUUID = UUID(uuidString: r.workID),
                  let studentIDUUID = UUID(uuidString: r.studentID) else { return nil }
            return WorkCompletionRecordDTO(
                id: r.id,
                workID: workIDUUID,
                studentID: studentIDUUID,
                completedAt: r.completedAt
            )
        }
    }

    /// Converts an array of Projects to ProjectDTOs
    static func toDTOs(_ projects: [Project]) -> [ProjectDTO] {
        projects.map { c in
            ProjectDTO(
                id: c.id,
                createdAt: c.createdAt,
                title: c.title,
                bookTitle: c.bookTitle,
                memberStudentIDs: c.memberStudentIDs
            )
        }
    }

    /// Converts an array of ProjectAssignmentTemplates to ProjectAssignmentTemplateDTOs
    static func toDTOs(_ projectTemplates: [ProjectAssignmentTemplate]) -> [ProjectAssignmentTemplateDTO] {
        projectTemplates.compactMap { t in
            guard let projectIDUUID = UUID(uuidString: t.projectID) else { return nil }
            return ProjectAssignmentTemplateDTO(
                id: t.id,
                createdAt: t.createdAt,
                projectID: projectIDUUID,
                title: t.title,
                instructions: t.instructions,
                isShared: t.isShared,
                defaultLinkedLessonID: t.defaultLinkedLessonID
            )
        }
    }

    /// Converts an array of ProjectSessions to ProjectSessionDTOs
    static func toDTOs(_ projectSessions: [ProjectSession]) -> [ProjectSessionDTO] {
        projectSessions.compactMap { s in
            guard let projectIDUUID = UUID(uuidString: s.projectID) else { return nil }
            let templateWeekIDUUID = s.templateWeekID.flatMap { UUID(uuidString: $0) }
            return ProjectSessionDTO(
                id: s.id,
                createdAt: s.createdAt,
                projectID: projectIDUUID,
                meetingDate: s.meetingDate,
                chapterOrPages: s.chapterOrPages,
                agendaItemsJSON: s.agendaItemsJSON,
                templateWeekID: templateWeekIDUUID
            )
        }
    }

    /// Converts an array of ProjectRoles to ProjectRoleDTOs
    static func toDTOs(_ projectRoles: [ProjectRole]) -> [ProjectRoleDTO] {
        projectRoles.compactMap { r in
            guard let projectIDUUID = UUID(uuidString: r.projectID) else { return nil }
            return ProjectRoleDTO(
                id: r.id,
                createdAt: r.createdAt,
                projectID: projectIDUUID,
                title: r.title,
                summary: r.summary,
                instructions: r.instructions
            )
        }
    }

    /// Converts an array of ProjectTemplateWeeks to ProjectTemplateWeekDTOs
    static func toDTOs(_ projectWeeks: [ProjectTemplateWeek]) -> [ProjectTemplateWeekDTO] {
        projectWeeks.compactMap { w in
            guard let projectIDUUID = UUID(uuidString: w.projectID) else { return nil }
            return ProjectTemplateWeekDTO(
                id: w.id,
                createdAt: w.createdAt,
                projectID: projectIDUUID,
                weekIndex: w.weekIndex,
                readingRange: w.readingRange,
                agendaItemsJSON: w.agendaItemsJSON,
                linkedLessonIDsJSON: w.linkedLessonIDsJSON,
                workInstructions: w.workInstructions
            )
        }
    }

    /// Converts an array of ProjectWeekRoleAssignments to ProjectWeekRoleAssignmentDTOs
    static func toDTOs(_ projectWeekAssignments: [ProjectWeekRoleAssignment]) -> [ProjectWeekRoleAssignmentDTO] {
        projectWeekAssignments.compactMap { a in
            guard let weekIDUUID = UUID(uuidString: a.weekID),
                  let roleIDUUID = UUID(uuidString: a.roleID) else { return nil }
            return ProjectWeekRoleAssignmentDTO(
                id: a.id,
                createdAt: a.createdAt,
                weekID: weekIDUUID,
                studentID: a.studentID,
                roleID: roleIDUUID
            )
        }
    }

    // MARK: - Envelope Building

    /// Builds a BackupEnvelope with common configuration
    static func buildEnvelope(
        payload: BackupPayload? = nil,
        encryptedPayload: Data? = nil,
        compressedPayload: Data? = nil,
        entityCounts: [String: Int],
        sha256: String,
        notes: String? = nil
    ) -> BackupEnvelope {
        BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: BackupManifest(
                entityCounts: entityCounts,
                sha256: sha256,
                notes: notes,
                compression: BackupFile.compressionAlgorithm
            ),
            payload: payload,
            encryptedPayload: encryptedPayload,
            compressedPayload: compressedPayload
        )
    }

    // MARK: - File Operations

    /// Writes encoded envelope data to a URL with atomic write
    static func writeBackupFile(envelope: BackupEnvelope, to url: URL, encoder: JSONEncoder) throws {
        let envBytes = try encoder.encode(envelope)

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("⚠️ [Backup:writeBackupFile] Failed to remove existing file at \(url.lastPathComponent): \(error)")
            }
        }
        try envBytes.write(to: url, options: .atomic)
    }

    // MARK: - Entity Filtering

    /// Filters entities by student IDs
    static func filterByStudents<T>(_ entities: [T], studentIDs: Set<UUID>?, studentIDExtractor: (T) -> UUID?) -> [T] {
        guard let studentIDs = studentIDs else { return entities }
        return entities.filter { entity in
            guard let sid = studentIDExtractor(entity) else { return false }
            return studentIDs.contains(sid)
        }
    }

    /// Filters entities by date range
    static func filterByDateRange<T>(_ entities: [T], dateRange: ClosedRange<Date>?, dateExtractor: (T) -> Date?) -> [T] {
        guard let range = dateRange else { return entities }
        return entities.filter { entity in
            guard let date = dateExtractor(entity) else { return true }
            return range.contains(date)
        }
    }

    /// Filters entities by project IDs
    static func filterByProjects<T>(_ entities: [T], projectIDs: Set<UUID>?, projectIDExtractor: (T) -> UUID?) -> [T] {
        guard let projectIDs = projectIDs else { return entities }
        return entities.filter { entity in
            guard let pid = projectIDExtractor(entity) else { return false }
            return projectIDs.contains(pid)
        }
    }

    // MARK: - Simple DTO Conversions

    static func toDTOs(_ nonSchoolDays: [NonSchoolDay]) -> [NonSchoolDayDTO] {
        nonSchoolDays.map { NonSchoolDayDTO(id: $0.id, date: $0.date, reason: $0.reason) }
    }

    static func toDTOs(_ schoolDayOverrides: [SchoolDayOverride]) -> [SchoolDayOverrideDTO] {
        schoolDayOverrides.map { SchoolDayOverrideDTO(id: $0.id, date: $0.date) }
    }

    static func toDTOs(_ studentMeetings: [StudentMeeting]) -> [StudentMeetingDTO] {
        studentMeetings.compactMap { m in
            guard let studentIDUUID = UUID(uuidString: m.studentID) else { return nil }
            return StudentMeetingDTO(
                id: m.id,
                studentID: studentIDUUID,
                date: m.date,
                completed: m.completed,
                reflection: m.reflection,
                focus: m.focus,
                requests: m.requests,
                guideNotes: m.guideNotes
            )
        }
    }

    static func toDTOs(_ communityTopics: [CommunityTopic]) -> [CommunityTopicDTO] {
        communityTopics.map { t in
            CommunityTopicDTO(
                id: t.id,
                title: t.title,
                issueDescription: t.issueDescription,
                createdAt: t.createdAt,
                addressedDate: t.addressedDate,
                resolution: t.resolution,
                raisedBy: t.raisedBy,
                tags: t.tags
            )
        }
    }

    static func toDTOs(_ proposedSolutions: [ProposedSolution]) -> [ProposedSolutionDTO] {
        proposedSolutions.map { s in
            ProposedSolutionDTO(
                id: s.id,
                topicID: s.topic?.id,
                title: s.title,
                details: s.details,
                proposedBy: s.proposedBy,
                createdAt: s.createdAt,
                isAdopted: s.isAdopted
            )
        }
    }

    static func toDTOs(_ communityAttachments: [CommunityAttachment]) -> [CommunityAttachmentDTO] {
        communityAttachments.map { a in
            CommunityAttachmentDTO(
                id: a.id,
                topicID: a.topic?.id,
                filename: a.filename,
                kind: a.kind.rawValue,
                createdAt: a.createdAt
            )
        }
    }
}

/// Helper for deduplicating backup payloads
@MainActor
enum BackupPayloadDeduplicator {

    /// Removes duplicate records from the backup payload, keeping the first occurrence of each ID.
    /// This handles backups created from databases that had duplicate records due to CloudKit sync issues.
    static func deduplicate(_ payload: BackupPayload) -> BackupPayload {
        func uniqueBy<T>(_ items: [T], id: (T) -> UUID) -> [T] {
            var seen = Set<UUID>()
            return items.filter { item in
                let itemId = id(item)
                guard !seen.contains(itemId) else { return false }
                seen.insert(itemId)
                return true
            }
        }

        var result = BackupPayload(
            items: payload.items,
            students: uniqueBy(payload.students) { $0.id },
            lessons: uniqueBy(payload.lessons) { $0.id },
            studentLessons: uniqueBy(payload.studentLessons) { $0.id },
            lessonAssignments: uniqueBy(payload.lessonAssignments) { $0.id },
            notes: uniqueBy(payload.notes) { $0.id },
            nonSchoolDays: uniqueBy(payload.nonSchoolDays) { $0.id },
            schoolDayOverrides: uniqueBy(payload.schoolDayOverrides) { $0.id },
            studentMeetings: uniqueBy(payload.studentMeetings) { $0.id },
            communityTopics: uniqueBy(payload.communityTopics) { $0.id },
            proposedSolutions: uniqueBy(payload.proposedSolutions) { $0.id },
            communityAttachments: uniqueBy(payload.communityAttachments) { $0.id },
            attendance: uniqueBy(payload.attendance) { $0.id },
            workCompletions: uniqueBy(payload.workCompletions) { $0.id },
            projects: uniqueBy(payload.projects) { $0.id },
            projectAssignmentTemplates: uniqueBy(payload.projectAssignmentTemplates) { $0.id },
            projectSessions: uniqueBy(payload.projectSessions) { $0.id },
            projectRoles: uniqueBy(payload.projectRoles) { $0.id },
            projectTemplateWeeks: uniqueBy(payload.projectTemplateWeeks) { $0.id },
            projectWeekRoleAssignments: uniqueBy(payload.projectWeekRoleAssignments) { $0.id },
            preferences: payload.preferences
        )
        
        // Format v8+ entity deduplication
        result.workCheckIns = payload.workCheckIns.map { uniqueBy($0) { $0.id } }
        result.workSteps = payload.workSteps.map { uniqueBy($0) { $0.id } }
        result.workParticipants = payload.workParticipants.map { uniqueBy($0) { $0.id } }
        result.practiceSessions = payload.practiceSessions.map { uniqueBy($0) { $0.id } }
        result.lessonAttachments = payload.lessonAttachments.map { uniqueBy($0) { $0.id } }
        result.lessonPresentations = payload.lessonPresentations.map { uniqueBy($0) { $0.id } }
        result.noteTemplates = payload.noteTemplates.map { uniqueBy($0) { $0.id } }
        result.meetingTemplates = payload.meetingTemplates.map { uniqueBy($0) { $0.id } }
        result.reminders = payload.reminders.map { uniqueBy($0) { $0.id } }
        result.calendarEvents = payload.calendarEvents.map { uniqueBy($0) { $0.id } }
        result.tracks = payload.tracks.map { uniqueBy($0) { $0.id } }
        result.trackSteps = payload.trackSteps.map { uniqueBy($0) { $0.id } }
        result.studentTrackEnrollments = payload.studentTrackEnrollments.map { uniqueBy($0) { $0.id } }
        result.groupTracks = payload.groupTracks.map { uniqueBy($0) { $0.id } }
        result.documents = payload.documents.map { uniqueBy($0) { $0.id } }
        result.supplies = payload.supplies.map { uniqueBy($0) { $0.id } }
        result.supplyTransactions = payload.supplyTransactions.map { uniqueBy($0) { $0.id } }
        result.procedures = payload.procedures.map { uniqueBy($0) { $0.id } }
        result.schedules = payload.schedules.map { uniqueBy($0) { $0.id } }
        result.scheduleSlots = payload.scheduleSlots.map { uniqueBy($0) { $0.id } }
        result.issues = payload.issues.map { uniqueBy($0) { $0.id } }
        result.issueActions = payload.issueActions.map { uniqueBy($0) { $0.id } }
        result.developmentSnapshots = payload.developmentSnapshots.map { uniqueBy($0) { $0.id } }
        result.todoItems = payload.todoItems.map { uniqueBy($0) { $0.id } }
        result.todoSubtasks = payload.todoSubtasks.map { uniqueBy($0) { $0.id } }
        result.todoTemplates = payload.todoTemplates.map { uniqueBy($0) { $0.id } }
        result.todayAgendaOrders = payload.todayAgendaOrders.map { uniqueBy($0) { $0.id } }
        
        return result
    }
}
