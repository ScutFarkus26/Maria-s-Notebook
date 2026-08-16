import Foundation
import CoreData
import OSLog

// MARK: - Format v18 Importers
//
// DTO -> CD object importers for the entity types added to backup coverage in
// format v18: CDDayPad, CDYearPlanEntry, CDLessonSequenceSettings, CDStory,
// CDBookClubPacket, CDBookClubSession, CDBookClubMeeting.
//
// Book Club imports are ordered packet -> session -> meeting by the caller so
// that `importBookClubMeetings` can re-wire each meeting's `session`
// relationship (the inverse of `BookClubSession.meetings`).

extension BackupEntityImporter {

    // MARK: - CDDayPad

    static func importDayPads(
        _ dtos: [DayPadDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            // CDDayPad's only convenience init requires a `day`; pass a placeholder
            // then restore the exact stored value (including nil) below.
            let pad = CDDayPad(context: viewContext, day: dto.day ?? Date())
            pad.id = dto.id
            pad.day = dto.day
            pad.body = dto.body
            pad.createdAt = dto.createdAt
            pad.modifiedAt = dto.modifiedAt
            viewContext.insert(pad)
        }
    }

    // MARK: - CDYearPlanEntry

    static func importYearPlanEntries(
        _ dtos: [YearPlanEntryDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let entry = CDYearPlanEntry(context: viewContext)
            entry.id = dto.id
            entry.studentID = dto.studentID
            entry.lessonID = dto.lessonID
            entry.plannedDate = dto.plannedDate
            entry.spacingSchoolDays = Int64(dto.spacingSchoolDays)
            entry.sequenceGroupKey = dto.sequenceGroupKey
            entry.orderInSequence = Int64(dto.orderInSequence)
            entry.statusRaw = dto.statusRaw
            entry.promotedAssignmentID = dto.promotedAssignmentID
            entry.createdAt = dto.createdAt
            entry.modifiedAt = dto.modifiedAt
            return entry
        })
    }

    // MARK: - CDLessonSequenceSettings

    static func importLessonSequenceSettings(
        _ dtos: [LessonSequenceSettingsDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let settings = CDLessonSequenceSettings(context: viewContext)
            settings.id = dto.id
            settings.area = dto.area
            settings.sequence = dto.sequence
            settings.requiresPractice = dto.requiresPractice
            settings.requiresTeacherConfirmation = dto.requiresTeacherConfirmation
            settings.createdAt = dto.createdAt
            settings.modifiedAt = dto.modifiedAt
            return settings
        })
    }

    // MARK: - CDStory

    static func importStories(
        _ dtos: [StoryDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let story = CDStory(context: viewContext)
            story.id = dto.id
            story.title = dto.title
            story.summary = dto.summary
            story.gradeMinRaw = dto.gradeMinRaw
            story.gradeMaxRaw = dto.gradeMaxRaw
            story.themesArray = dto.themes
            story.pdfFileRelativePath = dto.pdfFileRelativePath
            story.pageCount = Int32(dto.pageCount)
            story.createdAt = dto.createdAt
            story.modifiedAt = dto.modifiedAt
            story.analysisStatusRaw = dto.analysisStatusRaw
            story.analysisErrorMessage = dto.analysisErrorMessage
            story.analysisModelVersion = dto.analysisModelVersion
            story.extractedTextHash = dto.extractedTextHash
            story.userEditedTitle = dto.userEditedTitle
            story.userEditedThemes = dto.userEditedThemes
            story.relatedLessonIDsRaw = dto.relatedLessonIDsRaw
            story.relatedLessonReasonsJSON = dto.relatedLessonReasonsJSON
            story.relatedLessonsAnalyzedAt = dto.relatedLessonsAnalyzedAt
            // pdfFileBookmark / thumbnailData / generatedCoverData not backed up.
            return story
        })
    }

    // MARK: - CDBookClubPacket

    static func importBookClubPackets(
        _ dtos: [BookClubPacketDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let packet = CDBookClubPacket(context: viewContext)
            packet.id = dto.id
            packet.title = dto.title
            packet.author = dto.author
            packet.gradeMinRaw = dto.gradeMinRaw
            packet.gradeMaxRaw = dto.gradeMaxRaw
            packet.themesArray = dto.themes
            packet.teachingNotes = dto.teachingNotes
            packet.packetPDFRelativePath = dto.packetPDFRelativePath
            packet.pageCount = Int32(dto.pageCount)
            packet.readingItemsJSON = dto.readingItemsJSON
            packet.createdAt = dto.createdAt
            packet.modifiedAt = dto.modifiedAt
            // packetPDFBookmark / thumbnailData not backed up.
            return packet
        })
    }

    // MARK: - CDBookClubSession

    static func importBookClubSessions(
        _ dtos: [BookClubSessionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let session = CDBookClubSession(context: viewContext)
            session.id = dto.id
            session.packetID = dto.packetID
            session.displayName = dto.displayName
            session.startDate = dto.startDate
            session.endDate = dto.endDate
            session.cadenceRaw = dto.cadenceRaw
            session.meetingWeekdayMask = Int64(dto.meetingWeekdayMask)
            session.statusRaw = dto.statusRaw
            session.studentIDsRaw = dto.studentIDsRaw
            session.rotateLeader = dto.rotateLeader
            session.notes = dto.notes
            session.createdAt = dto.createdAt
            session.modifiedAt = dto.modifiedAt
            return session
        })
    }

    // MARK: - CDBookClubMeeting

    static func importBookClubMeetings(
        _ dtos: [BookClubMeetingDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck,
        sessionCheck: EntityLookup<CDBookClubSession>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let meeting = CDBookClubMeeting(context: viewContext)
            meeting.id = dto.id
            meeting.sessionID = dto.sessionID
            meeting.ordinal = Int32(dto.ordinal)
            meeting.date = dto.date
            meeting.readingLabel = dto.readingLabel
            meeting.leaderStudentID = dto.leaderStudentID
            meeting.isCompleted = dto.isCompleted
            meeting.completedAt = dto.completedAt
            meeting.notes = dto.notes
            meeting.createdAt = dto.createdAt
            meeting.modifiedAt = dto.modifiedAt
            // Re-wire the session relationship (inverse of BookClubSession.meetings).
            if let sessionUUID = UUID(uuidString: dto.sessionID) {
                do {
                    if let session = try sessionCheck(sessionUUID) {
                        meeting.session = session
                    }
                } catch {
                    Logger.backup.warning(
                        "Failed to check session for book club meeting: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            viewContext.insert(meeting)
        }
    }
}
