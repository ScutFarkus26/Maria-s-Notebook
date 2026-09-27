import Foundation
import CoreData

// MARK: - Format v18 Transformers
//
// CD object -> DTO transformers for the entity types added to backup coverage
// in format v18 (Stories, Book Club, Year Plan, Lesson Sequence Settings, Day
// Pads). Large binary blobs are intentionally not read here — only the
// portable relative file path is carried into the DTO.

extension BackupDTOTransformers {

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

}
