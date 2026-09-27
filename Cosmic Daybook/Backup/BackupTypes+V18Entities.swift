import Foundation

// MARK: - Format v18 DTOs
//
// Backup coverage for entity types that were previously listed in
// `BackupEntityRegistry.allTypes` for schema completeness but had no DTO,
// transformer, or importer:
//   - CDDayPad                (per-date scratchpad)
//   - CDYearPlanEntry         (year planning)
//   - CDLessonSequenceSettings(progression rules per area+sequence)
//   - CDStory                 (Stories library)
//   - CDBookClubPacket        (Book Club book/packet)
//   - CDBookClubSession       (Book Club session)
//   - CDBookClubMeeting       (Book Club meeting)
//
// Consistent with the rest of the backup, large binary blobs (PDF bookmarks,
// thumbnails, generated covers) are excluded by design — only the portable
// relative file path is preserved.

// MARK: - Story

nonisolated public struct StoryDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var gradeMinRaw: String
    public var gradeMaxRaw: String
    public var themes: [String]
    public var pdfFileRelativePath: String
    public var pageCount: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var analysisStatusRaw: String
    public var analysisErrorMessage: String
    public var analysisModelVersion: String
    public var extractedTextHash: String
    public var userEditedTitle: Bool
    public var userEditedThemes: Bool
    public var relatedLessonIDsRaw: String
    public var relatedLessonReasonsJSON: String
    public var relatedLessonsAnalyzedAt: Date?
    // Binary data (pdfFileBookmark, thumbnailData, generatedCoverData) excluded by design.
}

// MARK: - Book Club

nonisolated public struct BookClubPacketDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var author: String
    public var gradeMinRaw: String
    public var gradeMaxRaw: String
    public var themes: [String]
    public var teachingNotes: String
    public var packetPDFRelativePath: String
    public var pageCount: Int
    public var readingItemsJSON: String
    public var createdAt: Date
    public var modifiedAt: Date
    // Binary data (packetPDFBookmark, thumbnailData) excluded by design.
}
