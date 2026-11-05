// swiftlint:disable file_length
import CoreData
import Foundation
import OSLog
@testable import CosmicDaybook

// The backup's hand-written exports for the 38 entity types that "Simplify round
// two", Phase 7 moves to `ModelRow`, copied verbatim from a906650c0's
// `Backup/BackupServiceHelpers.swift` and `Backup/Export/BackupDTOTransformers.swift`,
// `+Core`, `+Work`, `+V18Entities` and `+Albums` (`+Misc` is in
// `LegacyBackupDTOTransformers+Misc.swift`). Only the names are changed:
// `BackupServiceHelpers` and `BackupDTOTransformers` are one enum,
// `LegacyBackupDTOTransformers` (the helpers' enum declares it, the
// transformers' empty one is an extension), and each DTO is its `Legacy` copy
// (`LegacyBackupDTOs.swift`). The legacy collector and `BackupSpecOracleTests`
// hold the table-driven export to these, so do not "fix" or modernise this code:
// its only job is to be the old code.

// MARK: - Backup/BackupServiceHelpers.swift

// Shared utilities for backup services

/// Shared helper utilities for backup operations (`BackupServiceHelpers` until Phase 7)
/// and `BackupDTOTransformers`, as one enum.
enum LegacyBackupDTOTransformers { // swiftlint:disable:this type_body_length
    private static let logger = Logger.backup

    // MARK: - DTO Conversion

    /// Converts an array of Students to StudentDTOs
    static func toDTOs(_ students: [CDStudent]) -> [LegacyStudentDTO] {
        students.compactMap { s in
            guard let sID = s.id else { return nil }
            let level: LegacyStudentDTO.Level
            switch s.level {
            case .lower: level = .lower
            case .upper: level = .upper
            case .adolescent: level = .adolescent
            }
            return LegacyStudentDTO(
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
                dateLastPromoted: s.dateLastPromoted,
                parentLockerID: s.parentLockerID,
                bornAfterSunset: s.bornAfterSunset
            )
        }
    }

    /// Converts an array of Lessons to LessonDTOs
    static func toDTOs(_ lessons: [CDLesson]) -> [LegacyLessonDTO] {
        lessons.compactMap { l in
            guard let lID = l.id else { return nil }
            return LegacyLessonDTO(
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
    static func toDTOs(_ notes: [CDNote]) -> [LegacyNoteDTO] {
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
            return LegacyNoteDTO(
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
                goingOutID: n.goingOutID,
                lessonAssignmentID: n.lessonAssignment?.id,
                attendanceRecordID: n.attendanceRecordID.flatMap { UUID(uuidString: $0) },
                workCheckInID: n.workCheckIn?.id,
                workCompletionRecordID: n.workCompletionRecord?.id,
                studentMeetingID: n.studentMeeting?.id,
                projectSessionID: n.projectSession?.id,
                reminderID: nil,
                issueID: n.issue?.id
            )
        }
    }

    /// Converts an array of AttendanceRecords to AttendanceRecordDTOs
    static func toDTOs(_ attendance: [CDAttendanceRecord]) -> [LegacyAttendanceRecordDTO] {
        attendance.compactMap { a in
            guard let aID = a.id,
                  let aDate = a.date,
                  let studentIDUUID = UUID(uuidString: a.studentID) else { return nil }
            return LegacyAttendanceRecordDTO(
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
    static func toDTOs(_ workCompletions: [CDWorkCompletionRecord]) -> [LegacyWorkCompletionRecordDTO] {
        workCompletions.compactMap { r in
            guard let rID = r.id,
                  let rCompletedAt = r.completedAt,
                  let workIDUUID = UUID(uuidString: r.workID),
                  let studentIDUUID = UUID(uuidString: r.studentID) else { return nil }
            return LegacyWorkCompletionRecordDTO(
                id: rID,
                workID: workIDUUID,
                studentID: studentIDUUID,
                completedAt: rCompletedAt
            )
        }
    }

    /// Converts an array of Projects to ProjectDTOs
    static func toDTOs(_ projects: [CDProject]) -> [LegacyProjectDTO] {
        projects.compactMap { c in
            guard let cID = c.id else { return nil }
            return LegacyProjectDTO(
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
    static func toDTOs(_ projectSessions: [CDProjectSession]) -> [LegacyProjectSessionDTO] {
        projectSessions.compactMap { s in
            guard let sID = s.id,
                  let sMeetingDate = s.meetingDate,
                  let projectIDUUID = UUID(uuidString: s.projectID) else { return nil }
            let templateWeekIDUUID = s.templateWeekID.flatMap { UUID(uuidString: $0) }
            return LegacyProjectSessionDTO(
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
    static func toDTOs(_ projectRoles: [CDProjectRole]) -> [LegacyProjectRoleDTO] {
        projectRoles.compactMap { r in
            guard let rID = r.id,
                  let projectIDUUID = UUID(uuidString: r.projectID) else { return nil }
            return LegacyProjectRoleDTO(
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

    static func toDTOs(_ nonSchoolDays: [CDNonSchoolDay]) -> [LegacyNonSchoolDayDTO] {
        nonSchoolDays.compactMap { nsd in
            guard let nsdID = nsd.id, let nsdDate = nsd.date else { return nil }
            return LegacyNonSchoolDayDTO(id: nsdID, date: nsdDate, reason: nsd.reason)
        }
    }

    static func toDTOs(_ schoolDayOverrides: [CDSchoolDayOverride]) -> [LegacySchoolDayOverrideDTO] {
        schoolDayOverrides.compactMap { ovr in
            guard let ovrID = ovr.id, let ovrDate = ovr.date else { return nil }
            return LegacySchoolDayOverrideDTO(id: ovrID, date: ovrDate)
        }
    }

    static func toDTOs(_ studentMeetings: [CDStudentMeeting]) -> [LegacyStudentMeetingDTO] {
        studentMeetings.compactMap { m in
            guard let mID = m.id,
                  let mDate = m.date,
                  let studentIDUUID = UUID(uuidString: m.studentID) else { return nil }
            return LegacyStudentMeetingDTO(
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

    static func toDTOs(_ communityTopics: [CDCommunityTopicEntity]) -> [LegacyCommunityTopicDTO] {
        communityTopics.compactMap { t in
            guard let tID = t.id else { return nil }
            return LegacyCommunityTopicDTO(
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

    static func toDTOs(_ communityAttachments: [CDCommunityAttachment]) -> [LegacyCommunityAttachmentDTO] {
        communityAttachments.compactMap { a in
            guard let aID = a.id else { return nil }
            return LegacyCommunityAttachmentDTO(
                id: aID,
                topicID: a.topic?.id,
                filename: a.filename,
                kind: a.kind.rawValue,
                createdAt: a.createdAt ?? Date()
            )
        }
    }

}

// MARK: - Backup/Export/BackupDTOTransformers.swift

/// Handles transformation between domain models and backup DTOs.
///
/// This extracts the DTO transformation logic from BackupService for better
/// testability and separation of concerns.
///
/// Transformers are organized into domain-specific extensions:
/// - `LegacyBackupDTOTransformers+Core.swift` — CDLessonAttachment,
///   CDLessonPresentation, CDLessonRecallCheck, CDSampleWork, CDSampleWorkStep
/// - `LegacyBackupDTOTransformers+Work.swift` — CDWorkCheckIn, CDWorkStep,
///   WorkParticipant
/// - `LegacyBackupDTOTransformers+V18Entities.swift` — CDDayPad, CDYearPlanEntry,
///   CDLessonSequenceSettings, CDStory, Book Club entities
/// - `LegacyBackupDTOTransformers+Misc.swift` — Calendar, Todo,
///   CDSupply, CDSchedule, CDIssue, CDProcedure, CDDocument, and remaining types
///
/// Entities NOT handled here (CDStudent, CDLesson, CDNote, CDNonSchoolDay,
/// CDSchoolDayOverride, CDStudentMeeting, CDAttendanceRecord,
/// CDWorkCompletionRecord, CDProject, CDProjectSession, CDProjectRole, and the
/// Community entities) are exported via `LegacyBackupDTOTransformers.toDTOs`, which
/// carries their full field set. Duplicating them here caused silent field loss
/// in the past — keep a single transformer per entity.
extension LegacyBackupDTOTransformers {
    // MARK: - WorkPlanItem - REMOVED IN PHASE 6
    // WorkPlanItem has been migrated to CDWorkCheckIn and removed from schema

    // MARK: - CDPresentation (Removed)
    // CDPresentation model has been removed. Use CDLessonAssignment instead.
}

// MARK: - Backup/Export/BackupDTOTransformers+Core.swift

// MARK: - Core Transformers (CDSampleWork, CDSampleWorkStep, CDLessonAttachment,
//         CDLessonPresentation, CDLessonRecallCheck)
// CDStudent, CDLesson, and CDNote exports go through LegacyBackupDTOTransformers.toDTOs,
// which carries the full field set — do not re-add transformers for them here.

extension LegacyBackupDTOTransformers {

    // MARK: - CDSampleWork

    static func toDTO(_ sw: CDSampleWork) -> LegacySampleWorkDTO {
        LegacySampleWorkDTO(
            id: sw.id ?? UUID(),
            lessonID: (sw.lesson as? CDLesson)?.id,
            title: sw.title,
            workKindRaw: sw.workKindRaw,
            orderIndex: Int(sw.orderIndex),
            notes: sw.notes,
            createdAt: sw.createdAt ?? Date()
        )
    }

    // MARK: - CDLessonPresentation

    static func toDTO(_ lp: CDLessonPresentation) -> LegacyLessonPresentationDTO {
        LegacyLessonPresentationDTO(
            id: lp.id ?? UUID(),
            createdAt: lp.createdAt ?? Date(),
            studentID: lp.studentID,
            lessonID: lp.lessonID,
            presentationID: lp.presentationID,
            stateRaw: lp.stateRaw,
            presentedAt: lp.presentedAt ?? Date(),
            lastObservedAt: lp.lastObservedAt,
            masteredAt: lp.masteredAt,
            notes: lp.notes,
            followUpActionRaw: lp.followUpActionRaw,
            followUpReviewAt: lp.followUpReviewAt,
            followUpResolvedAt: lp.followUpResolvedAt,
            followUpResolutionRaw: lp.followUpResolutionRaw,
            followUpUpdatedAt: lp.followUpUpdatedAt,
            followUpEvidenceRaw: lp.followUpEvidenceRaw,
            followUpNote: lp.followUpNote,
            followUpSupportRaw: lp.followUpSupportRaw
        )
    }

    // MARK: - Batch Transformations (Core)

    static func toDTOs(_ sampleWorks: [CDSampleWork]) -> [LegacySampleWorkDTO] {
        sampleWorks.map { toDTO($0) }
    }

    static func toDTOs(_ presentations: [CDLessonPresentation]) -> [LegacyLessonPresentationDTO] {
        presentations.map { toDTO($0) }
    }

}

// MARK: - Backup/Export/BackupDTOTransformers+Work.swift

// MARK: - Work Transformers (CDWorkModel, CDWorkCheckIn, CDWorkStep, WorkParticipant)

extension LegacyBackupDTOTransformers {

    // MARK: - CDWorkModel

    static func toDTO(_ work: CDWorkModel) -> LegacyWorkModelDTO {
        LegacyWorkModelDTO(
            id: work.id ?? UUID(),
            title: work.title,
            workTypeRaw: work.workTypeRaw,
            studentLessonID: work.studentLessonID,
            createdAt: work.createdAt ?? Date(),
            completedAt: work.completedAt,
            kindRaw: work.kindRaw,
            statusRaw: work.statusRaw,
            assignedAt: work.assignedAt ?? Date(),
            lastTouchedAt: work.lastTouchedAt,
            dueAt: work.dueAt,
            completionOutcomeRaw: work.completionOutcomeRaw,
            studentID: work.studentID,
            lessonID: work.lessonID,
            presentationID: work.presentationID,
            scheduledNote: work.scheduledNote,
            scheduledReasonRaw: work.scheduledReasonRaw,
            sourceContextTypeRaw: work.sourceContextTypeRaw,
            sourceContextID: work.sourceContextID,
            sampleWorkID: work.sampleWorkID,
            checkInStyleRaw: work.checkInStyleRaw,
            restingUntil: work.restingUntil
        )
    }

    // MARK: - CDWorkCheckIn

    static func toDTO(_ checkIn: CDWorkCheckIn) -> LegacyWorkCheckInDTO {
        LegacyWorkCheckInDTO(
            id: checkIn.id ?? UUID(),
            workID: checkIn.workID,
            date: checkIn.date ?? Date(),
            statusRaw: checkIn.statusRaw,
            purpose: checkIn.purpose,
            studentInitiated: checkIn.studentInitiated,
            durationMinutes: checkIn.durationMinutesValue
        )
    }

    // MARK: - CDWorkParticipantEntity

    static func toDTO(_ participant: CDWorkParticipantEntity) -> LegacyWorkParticipantEntityDTO {
        LegacyWorkParticipantEntityDTO(
            id: participant.id ?? UUID(),
            studentID: participant.studentID,
            completedAt: participant.completedAt,
            workID: participant.work?.id
        )
    }

    // MARK: - Batch Transformations (Work)

    static func toDTOs(_ works: [CDWorkModel]) -> [LegacyWorkModelDTO] {
        works.map { toDTO($0) }
    }

    static func toDTOs(_ checkIns: [CDWorkCheckIn]) -> [LegacyWorkCheckInDTO] {
        checkIns.map { toDTO($0) }
    }

    static func toDTOs(_ participants: [CDWorkParticipantEntity]) -> [LegacyWorkParticipantEntityDTO] {
        participants.map { toDTO($0) }
    }
}

// MARK: - Backup/Export/BackupDTOTransformers+V18Entities.swift

// MARK: - Format v18 Transformers
//
// CD object -> DTO transformers for the entity types added to backup coverage
// in format v18 (Stories, Book Club, Year Plan, Lesson Sequence Settings, Day
// Pads). Large binary blobs are intentionally not read here — only the
// portable relative file path is carried into the DTO.

extension LegacyBackupDTOTransformers {

    // MARK: - CDStory

    static func toDTO(_ story: CDStory) -> LegacyStoryDTO {
        LegacyStoryDTO(
            id: story.id ?? UUID(),
            title: story.title,
            summary: story.summary,
            gradeMinRaw: story.gradeMinRaw,
            gradeMaxRaw: story.gradeMaxRaw,
            themes: story.themesArray,
            pdfFileRelativePath: story.pdfFileRelativePath,
            pageCount: Int(story.pageCount),
            createdAt: story.createdAt ?? Date(),
            modifiedAt: story.modifiedAt ?? Date(),
            analysisStatusRaw: story.analysisStatusRaw,
            analysisErrorMessage: story.analysisErrorMessage,
            analysisModelVersion: story.analysisModelVersion,
            extractedTextHash: story.extractedTextHash,
            userEditedTitle: story.userEditedTitle,
            userEditedThemes: story.userEditedThemes,
            relatedLessonIDsRaw: story.relatedLessonIDsRaw,
            relatedLessonReasonsJSON: story.relatedLessonReasonsJSON,
            relatedLessonsAnalyzedAt: story.relatedLessonsAnalyzedAt
        )
    }

    static func toDTOs(_ stories: [CDStory]) -> [LegacyStoryDTO] {
        stories.map { toDTO($0) }
    }

    // MARK: - CDBookClubPacket

    static func toDTO(_ packet: CDBookClubPacket) -> LegacyBookClubPacketDTO {
        LegacyBookClubPacketDTO(
            id: packet.id ?? UUID(),
            title: packet.title,
            author: packet.author,
            gradeMinRaw: packet.gradeMinRaw,
            gradeMaxRaw: packet.gradeMaxRaw,
            themes: packet.themesArray,
            teachingNotes: packet.teachingNotes,
            packetPDFRelativePath: packet.packetPDFRelativePath,
            pageCount: Int(packet.pageCount),
            readingItemsJSON: packet.readingItemsJSON,
            createdAt: packet.createdAt ?? Date(),
            modifiedAt: packet.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ packets: [CDBookClubPacket]) -> [LegacyBookClubPacketDTO] {
        packets.map { toDTO($0) }
    }

}

// MARK: - Backup/Export/BackupDTOTransformers+Albums.swift

// MARK: - Format v21 Transformers
//
// CD object -> DTO transformers for teaching-album annotations. Unlike the
// other features, two binary attributes are carried through: highlight
// rectangles (decoded to plain numbers) and PencilKit ink. Neither can be
// regenerated after a restore, so both belong in the archive.

extension LegacyBackupDTOTransformers {

    // MARK: - CDAlbumHighlight

    static func toDTO(_ highlight: CDAlbumHighlight) -> LegacyAlbumHighlightDTO {
        LegacyAlbumHighlightDTO(
            id: highlight.id ?? UUID(),
            albumID: highlight.albumID,
            pageIndex: Int(highlight.pageIndex),
            lessonTitle: highlight.lessonTitle,
            text: highlight.text,
            colorName: highlight.colorName,
            rects: highlight.rectValues,
            createdAt: highlight.createdAt ?? Date(),
            modifiedAt: highlight.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ highlights: [CDAlbumHighlight]) -> [LegacyAlbumHighlightDTO] {
        highlights.map { toDTO($0) }
    }

    // MARK: - CDAlbumPageInk

    static func toDTO(_ ink: CDAlbumPageInk) -> LegacyAlbumPageInkDTO {
        LegacyAlbumPageInkDTO(
            id: ink.id ?? UUID(),
            albumID: ink.albumID,
            pageIndex: Int(ink.pageIndex),
            drawingData: ink.drawingData ?? Data(),
            modifiedAt: ink.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ ink: [CDAlbumPageInk]) -> [LegacyAlbumPageInkDTO] {
        ink.map { toDTO($0) }
    }
}
