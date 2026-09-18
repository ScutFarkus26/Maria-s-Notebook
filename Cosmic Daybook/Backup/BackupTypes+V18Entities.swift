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

// MARK: - Day Pad

nonisolated public struct DayPadDTO: Codable, Sendable {
    public var id: UUID
    public var day: Date?
    public var body: String?
    public var createdAt: Date
    public var modifiedAt: Date
}

// MARK: - Year Plan

nonisolated public struct YearPlanEntryDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var lessonID: String
    public var plannedDate: Date?
    public var spacingSchoolDays: Int
    public var sequenceGroupKey: String
    public var orderInSequence: Int
    public var statusRaw: String
    public var promotedAssignmentID: String?
    public var createdAt: Date
    public var modifiedAt: Date
}

// MARK: - Lesson Sequence Settings

nonisolated public struct LessonSequenceSettingsDTO: Codable, Sendable {
    public var id: UUID
    public var area: String
    public var sequence: String
    public var requiresPractice: Bool
    public var requiresTeacherConfirmation: Bool
    public var createdAt: Date
    public var modifiedAt: Date
}

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

nonisolated public struct BookClubSessionDTO: Codable, Sendable {
    public var id: UUID
    public var packetID: String
    public var displayName: String
    public var startDate: Date?
    public var endDate: Date?
    public var cadenceRaw: String
    public var meetingWeekdayMask: Int
    public var statusRaw: String
    public var studentIDsRaw: String
    public var rotateLeader: Bool
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated public struct BookClubMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var sessionID: String
    public var ordinal: Int
    public var date: Date?
    public var readingLabel: String
    public var leaderStudentID: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
}
