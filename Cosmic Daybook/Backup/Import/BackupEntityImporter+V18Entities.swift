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

    // MARK: - CDStory

    static func importStories(
        _ dtos: [StoryDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDStory>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let story = current ?? CDStory(context: viewContext)
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
        existing: ExistingLookup<CDBookClubPacket>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let packet = current ?? CDBookClubPacket(context: viewContext)
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

}
