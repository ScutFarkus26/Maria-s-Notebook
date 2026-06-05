import Foundation
import CoreData

// MARK: - Format v18 Transformers
//
// CD object -> DTO transformers for the entity types added to backup coverage
// in format v18 (Stories, Book Club, Year Plan, Lesson Sequence Settings, Day
// Pads). Large binary blobs are intentionally not read here — only the
// portable relative file path is carried into the DTO.

extension BackupDTOTransformers {

    // MARK: - CDDayPad

    static func toDTO(_ pad: CDDayPad) -> DayPadDTO {
        DayPadDTO(
            id: pad.id ?? UUID(),
            day: pad.day,
            body: pad.body,
            createdAt: pad.createdAt ?? Date(),
            modifiedAt: pad.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ pads: [CDDayPad]) -> [DayPadDTO] {
        pads.map { toDTO($0) }
    }

    // MARK: - CDYearPlanEntry

    static func toDTO(_ entry: CDYearPlanEntry) -> YearPlanEntryDTO {
        YearPlanEntryDTO(
            id: entry.id ?? UUID(),
            studentID: entry.studentID,
            lessonID: entry.lessonID,
            plannedDate: entry.plannedDate,
            spacingSchoolDays: Int(entry.spacingSchoolDays),
            sequenceGroupKey: entry.sequenceGroupKey,
            orderInSequence: Int(entry.orderInSequence),
            statusRaw: entry.statusRaw,
            promotedAssignmentID: entry.promotedAssignmentID,
            createdAt: entry.createdAt ?? Date(),
            modifiedAt: entry.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ entries: [CDYearPlanEntry]) -> [YearPlanEntryDTO] {
        entries.map { toDTO($0) }
    }

    // MARK: - CDLessonSequenceSettings

    static func toDTO(_ settings: CDLessonSequenceSettings) -> LessonSequenceSettingsDTO {
        LessonSequenceSettingsDTO(
            id: settings.id ?? UUID(),
            area: settings.area,
            sequence: settings.sequence,
            requiresPractice: settings.requiresPractice,
            requiresTeacherConfirmation: settings.requiresTeacherConfirmation,
            createdAt: settings.createdAt ?? Date(),
            modifiedAt: settings.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ settings: [CDLessonSequenceSettings]) -> [LessonSequenceSettingsDTO] {
        settings.map { toDTO($0) }
    }

    // MARK: - CDStory

    static func toDTO(_ story: CDStory) -> StoryDTO {
        StoryDTO(
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

    static func toDTOs(_ stories: [CDStory]) -> [StoryDTO] {
        stories.map { toDTO($0) }
    }

    // MARK: - CDBookClubPacket

    static func toDTO(_ packet: CDBookClubPacket) -> BookClubPacketDTO {
        BookClubPacketDTO(
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

    static func toDTOs(_ packets: [CDBookClubPacket]) -> [BookClubPacketDTO] {
        packets.map { toDTO($0) }
    }

    // MARK: - CDBookClubSession

    static func toDTO(_ session: CDBookClubSession) -> BookClubSessionDTO {
        BookClubSessionDTO(
            id: session.id ?? UUID(),
            packetID: session.packetID,
            displayName: session.displayName,
            startDate: session.startDate,
            endDate: session.endDate,
            cadenceRaw: session.cadenceRaw,
            meetingWeekdayMask: Int(session.meetingWeekdayMask),
            statusRaw: session.statusRaw,
            studentIDsRaw: session.studentIDsRaw,
            rotateLeader: session.rotateLeader,
            notes: session.notes,
            createdAt: session.createdAt ?? Date(),
            modifiedAt: session.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ sessions: [CDBookClubSession]) -> [BookClubSessionDTO] {
        sessions.map { toDTO($0) }
    }

    // MARK: - CDBookClubMeeting

    static func toDTO(_ meeting: CDBookClubMeeting) -> BookClubMeetingDTO {
        BookClubMeetingDTO(
            id: meeting.id ?? UUID(),
            sessionID: meeting.sessionID,
            ordinal: Int(meeting.ordinal),
            date: meeting.date,
            readingLabel: meeting.readingLabel,
            leaderStudentID: meeting.leaderStudentID,
            isCompleted: meeting.isCompleted,
            completedAt: meeting.completedAt,
            notes: meeting.notes,
            createdAt: meeting.createdAt ?? Date(),
            modifiedAt: meeting.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ meetings: [CDBookClubMeeting]) -> [BookClubMeetingDTO] {
        meetings.map { toDTO($0) }
    }
}
