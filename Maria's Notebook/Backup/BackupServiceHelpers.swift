// swiftlint:disable file_length
// BackupServiceHelpers.swift
// Shared utilities for backup services

import Foundation
import CoreData
import OSLog

/// Shared helper utilities for backup operations
@MainActor
// swiftlint:disable:next type_body_length
enum BackupServiceHelpers {
    private static let logger = Logger.backup

    // MARK: - DTO Conversion

    /// Converts an array of Students to StudentDTOs
    static func toDTOs(_ students: [CDStudent]) -> [StudentDTO] {
        students.compactMap { s in
            guard let sID = s.id else { return nil }
            let level: StudentDTO.Level = (s.level == .upper) ? .upper : .lower
            return StudentDTO(
                id: sID,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday ?? Date(),
                dateStarted: s.dateStarted,
                level: level,
                nextLessons: s.nextLessonUUIDs,
                manualOrder: Int(s.manualOrder),
                createdAt: nil,
                updatedAt: nil
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
                subject: l.subject,
                group: l.group,
                orderInGroup: Int(l.orderInGroup),
                subheading: l.subheading,
                writeUp: l.writeUp,
                createdAt: nil,
                updatedAt: nil,
                pagesFileRelativePath: l.pagesFileRelativePath
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
            return NoteDTO(
                id: nID,
                createdAt: n.createdAt ?? Date(),
                updatedAt: n.updatedAt ?? Date(),
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
                absenceReason: a.absenceReason.rawValue == "none" ? nil : a.absenceReason.rawValue
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
                memberStudentIDs: c.memberStudentIDsArray
            )
        }
    }

    /// Converts an array of ProjectAssignmentTemplates to ProjectAssignmentTemplateDTOs
    static func toDTOs(_ projectTemplates: [CDProjectAssignmentTemplate]) -> [ProjectAssignmentTemplateDTO] {
        projectTemplates.compactMap { t in
            guard let tID = t.id,
                  let projectIDUUID = UUID(uuidString: t.projectID) else { return nil }
            return ProjectAssignmentTemplateDTO(
                id: tID,
                createdAt: t.createdAt ?? Date(),
                projectID: projectIDUUID,
                title: t.title,
                instructions: t.instructions,
                isShared: t.isShared,
                defaultLinkedLessonID: t.defaultLinkedLessonID
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
                templateWeekID: templateWeekIDUUID
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

    /// Converts an array of ProjectTemplateWeeks to ProjectTemplateWeekDTOs
    static func toDTOs(_ projectWeeks: [CDProjectTemplateWeek]) -> [ProjectTemplateWeekDTO] {
        projectWeeks.compactMap { w in
            guard let wID = w.id,
                  let projectIDUUID = UUID(uuidString: w.projectID) else { return nil }
            return ProjectTemplateWeekDTO(
                id: wID,
                createdAt: w.createdAt ?? Date(),
                projectID: projectIDUUID,
                weekIndex: Int(w.weekIndex),
                readingRange: w.readingRange,
                agendaItemsJSON: w.agendaItemsJSON,
                linkedLessonIDsJSON: w.linkedLessonIDsJSON,
                workInstructions: w.workInstructions
            )
        }
    }

    /// Converts an array of ProjectWeekRoleAssignments to ProjectWeekRoleAssignmentDTOs
    static func toDTOs(_ projectWeekAssignments: [CDProjectWeekRoleAssignment]) -> [ProjectWeekRoleAssignmentDTO] {
        projectWeekAssignments.compactMap { a in
            guard let aID = a.id,
                  let weekIDUUID = UUID(uuidString: a.weekID),
                  let roleIDUUID = UUID(uuidString: a.roleID) else { return nil }
            return ProjectWeekRoleAssignmentDTO(
                id: aID,
                createdAt: a.createdAt ?? Date(),
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
                let name = url.lastPathComponent
                let desc = error.localizedDescription
                logger.warning("Failed to remove existing file at \(name, privacy: .public): \(desc, privacy: .public)")
            }
        }
        try envBytes.write(to: url, options: .atomic)
    }

    // MARK: - Entity Filtering

    /// Filters entities by student IDs
    static func filterByStudents<T>(_ entities: [T], studentIDs: Set<UUID>?, studentIDExtractor: (T) -> UUID?) -> [T] {
        guard let studentIDs else { return entities }
        return entities.filter { entity in
            guard let sid = studentIDExtractor(entity) else { return false }
            return studentIDs.contains(sid)
        }
    }

    /// Filters entities by date range
    static func filterByDateRange<T>(
        _ entities: [T],
        dateRange: ClosedRange<Date>?,
        dateExtractor: (T) -> Date?
    ) -> [T] {
        guard let range = dateRange else { return entities }
        return entities.filter { entity in
            guard let date = dateExtractor(entity) else { return true }
            return range.contains(date)
        }
    }

    /// Filters entities by project IDs
    static func filterByProjects<T>(_ entities: [T], projectIDs: Set<UUID>?, projectIDExtractor: (T) -> UUID?) -> [T] {
        guard let projectIDs else { return entities }
        return entities.filter { entity in
            guard let pid = projectIDExtractor(entity) else { return false }
            return projectIDs.contains(pid)
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

    static func toDTOs(_ proposedSolutions: [CDProposedSolutionEntity]) -> [ProposedSolutionDTO] {
        proposedSolutions.compactMap { s in
            guard let sID = s.id else { return nil }
            return ProposedSolutionDTO(
                id: sID,
                topicID: s.topic?.id,
                title: s.title,
                details: s.details,
                proposedBy: s.proposedBy,
                createdAt: s.createdAt ?? Date(),
                isAdopted: s.isAdopted
            )
        }
    }

    static func toDTOs(_ communityAttachments: [CDCommunityAttachmentEntity]) -> [CommunityAttachmentDTO] {
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

/// Helper for deduplicating backup payloads
@MainActor
enum BackupPayloadDeduplicator {

    // Removes duplicate records from the backup payload, keeping the first occurrence of each ID.
    // This handles backups created from databases that had duplicate records due to CloudKit sync issues.
    // swiftlint:disable:next function_body_length
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
        result.workModels = payload.workModels.map { uniqueBy($0) { $0.id } }
        result.workCheckIns = payload.workCheckIns.map { uniqueBy($0) { $0.id } }
        result.workSteps = payload.workSteps.map { uniqueBy($0) { $0.id } }
        result.workParticipants = payload.workParticipants.map { uniqueBy($0) { $0.id } }
        result.practiceSessions = payload.practiceSessions.map { uniqueBy($0) { $0.id } }
        result.lessonAttachments = payload.lessonAttachments.map { uniqueBy($0) { $0.id } }
        result.lessonPresentations = payload.lessonPresentations.map { uniqueBy($0) { $0.id } }
        result.sampleWorks = payload.sampleWorks.map { uniqueBy($0) { $0.id } }
        result.sampleWorkSteps = payload.sampleWorkSteps.map { uniqueBy($0) { $0.id } }
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
        // Format v11+ entity deduplication
        result.planningRecommendations = payload.planningRecommendations.map { uniqueBy($0) { $0.id } }
        result.resources = payload.resources.map { uniqueBy($0) { $0.id } }
        result.noteStudentLinks = payload.noteStudentLinks.map { uniqueBy($0) { $0.id } }
        // Format v12+ entity deduplication
        result.goingOuts = payload.goingOuts.map { uniqueBy($0) { $0.id } }
        result.goingOutChecklistItems = payload.goingOutChecklistItems.map { uniqueBy($0) { $0.id } }
        result.classroomJobs = payload.classroomJobs.map { uniqueBy($0) { $0.id } }
        result.jobAssignments = payload.jobAssignments.map { uniqueBy($0) { $0.id } }
        result.transitionPlans = payload.transitionPlans.map { uniqueBy($0) { $0.id } }
        result.transitionChecklistItems = payload.transitionChecklistItems.map { uniqueBy($0) { $0.id } }
        result.calendarNotes = payload.calendarNotes.map { uniqueBy($0) { $0.id } }
        result.scheduledMeetings = payload.scheduledMeetings.map { uniqueBy($0) { $0.id } }
        result.albumGroupOrders = payload.albumGroupOrders.map { uniqueBy($0) { $0.id } }
        result.albumGroupUIStates = payload.albumGroupUIStates.map { uniqueBy($0) { $0.id } }

        return result
    }
}
