// swiftlint:disable file_length
import Foundation
@testable import CosmicDaybook

// The backup's hand-written row types for the 38 entity types that "Simplify
// round two", Phase 7 moves to `ModelRow`, copied verbatim from a906650c0's
// `Backup/BackupTypes+Core.swift`, `+Albums`, `+CalendarAdmin`, `+Misc`,
// `+Projects`, `+V18Entities` and `+Work` (their lenient decoders and `BackupRowDTO`
// conformances are in `LegacyBackupDTOs+Decoding.swift`). Only the names are
// changed: each type is the app's prefixed `Legacy` (`StudentDTO` → `LegacyStudentDTO`),
// and internal rather than public, so the frozen `BackupRowDTO` conformances
// compile in this target.
// `ItemDTO` and the retired project template types are left out: no backed-up
// type fills them. With `LegacyBackupDTOTransformers` and
// `LegacyBackupEntityImporter` they are the old backup, which the legacy
// collector, the legacy restore and `BackupSpecOracleTests` hold the table-driven
// code to, so do not "fix" or modernise this code: its only job is to be the old code.

// MARK: - The boundary

/// Converts rows between the app's row types and their `Legacy` copies the way
/// a backup carries them: each row encoded as the archive writer's row encoder
/// writes it (`BackupWriter.ndjsonEncoder`, dates as `BackupDateCoding` writes
/// them), then decoded as the other type with the archive reader's dates. The
/// legacy collector, the legacy restore and `BackupSpecOracleTests` meet the app
/// here, so the frozen code keeps working whether the app's type is still a
/// hand-written struct or has become a `ModelRow`. A row the other type can't
/// decode is left out, as a reader of that type would have refused its line.
///
/// One difference from a real archive: a date read back as a date is the very
/// date written, not the one its text parses to. The archive keeps
/// milliseconds, and for about half of them parsing the text and writing it
/// again gives the millisecond before (a parse lands just under it and the
/// writer truncates), so a plain round trip would move dates the old code
/// wrote, or read, by a millisecond. A string read where a date was written
/// still gets the archive's text.
nonisolated enum LegacyRows {
    static func rows<To: Decodable, From: Encodable>(_ from: [From], as: To.Type) -> [To] {
        let written = DatesWritten()
        let encoder = BackupWriter.ndjsonEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let text = BackupDateCoding.string(from: date)
            written.note(date, as: text)
            var container = encoder.singleValueContainer()
            try container.encode(text)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = written.date(for: text) ?? BackupDateCoding.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Expected an ISO 8601 date, found \(text)"
                )
            }
            return date
        }
        return from.compactMap { row in
            written.removeAll()
            guard let line = try? encoder.encode(row) else { return nil }
            return try? decoder.decode(To.self, from: line)
        }
    }

    /// The dates one row's line was written from, by the text written for
    /// each (the first, when two dates write the same text: either one
    /// writes it again).
    private final class DatesWritten: @unchecked Sendable {
        private let lock = NSLock()
        private var dates: [String: Date] = [:]

        func note(_ date: Date, as text: String) {
            lock.withLock { if dates[text] == nil { dates[text] = date } }
        }

        func date(for text: String) -> Date? {
            lock.withLock { dates[text] }
        }

        func removeAll() {
            lock.withLock { dates.removeAll(keepingCapacity: true) }
        }
    }
}

// MARK: - Backup/BackupTypes+Core.swift

// MARK: - Core DTOs (Students, Lessons, Notes, and closely related types)

nonisolated struct LegacyStudentDTO: Codable, Sendable {
    public enum Level: String, Codable, Sendable { case lower, upper, adolescent }
    public var id: UUID
    public var firstName: String
    public var lastName: String
    // Optional: a student with no recorded birthday must export as nil, not a
    // fabricated date. Older backups always carry a value (sometimes fabricated —
    // Date() at export time or .distantPast); the importer filters sentinels.
    public var birthday: Date?
    public var dateStarted: Date?
    public var level: Level
    public var nextLessons: [UUID]
    public var manualOrder: Int
    public var createdAt: Date?
    public var updatedAt: Date?
    // Restored fields (optional for compatibility with older backups that predate them).
    public var nickname: String?
    public var enrollmentStatusRaw: String?
    public var dateWithdrawn: Date?
    /// Conflict-resolution timestamp, preserved so post-restore deduplication
    /// doesn't treat every restored student as "just modified". Optional for
    /// compatibility with older backups that predate this field.
    public var modifiedAt: Date?
    // Promotion record (optional for compatibility with older backups that predate them).
    public var previousLevelRaw: String?
    public var dateLastPromoted: Date?
    /// The child's match on the school's ParentLocker site (format v40+).
    /// Optional so older backups decode; restoring one keeps the record's own.
    public var parentLockerID: String?
    /// Whether the child was born after sunset, which moves her Hebrew
    /// birthday one day on (format v43+). Every v43 row says yes or no.
    /// Optional so older backups decode; restoring one keeps the record's own.
    public var bornAfterSunset: Bool?
}

nonisolated struct LegacyLessonDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var area: String
    public var sequence: String
    public var orderInSequence: Int
    public var section: String
    public var writeUp: String
    public var createdAt: Date?
    public var updatedAt: Date?
    // File-related fields are intentionally omitted; only include managed relative path if needed
    public var pagesFileRelativePath: String?
    public var primaryAttachmentID: UUID?
    // Montessori album fields (format v9+)
    public var suggestedFollowUpWork: String?
    public var sourceRaw: String?
    public var personalKindRaw: String?
    public var defaultWorkKindRaw: String?
    public var materials: String?
    public var purpose: String?
    public var ageRange: String?
    public var teacherNotes: String?
    public var prerequisiteLessonIDs: String?
    public var relatedLessonIDs: String?
    // Restored fields (optional for compatibility with older backups that predate them).
    public var parshaKey: String?
    public var greatLessonRaw: String?
    public var lessonFormatRaw: String?
    public var sortIndex: Int?
    public var derivedFromLessonID: String?
    public var parentStoryID: String?
    public var requiresPracticeOverride: String?
    public var requiresConfirmationOverride: String?
    // Teaching-album link (format v22+). Optional so v17–v21 backups decode.
    public var albumID: String?
    public var albumPageIndex: Int?
    public var albumLessonTitle: String?
    public var albumLinkConfidence: Double?
    // Three-Year View milestone flag (format v25+). Optional so older backups decode.
    public var isKeyLesson: Bool?
}

nonisolated struct LegacySampleWorkDTO: Codable, Sendable {
    public var id: UUID
    public var lessonID: UUID?
    public var title: String
    public var workKindRaw: String
    public var orderIndex: Int
    public var notes: String
    public var createdAt: Date
}

nonisolated struct LegacyLessonPresentationDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var studentID: String
    public var lessonID: String
    public var presentationID: String?
    public var trackID: String?
    public var trackStepID: String?
    public var stateRaw: String
    public var presentedAt: Date
    public var lastObservedAt: Date?
    // Codable DTO property, must match JSON key
    public var masteredAt: Date?
    public var notes: String?
    public var followUpActionRaw: String?
    public var followUpReviewAt: Date?
    public var followUpResolvedAt: Date?
    public var followUpResolutionRaw: String?
    public var followUpUpdatedAt: Date?
    public var followUpEvidenceRaw: String?
    public var followUpNote: String?
    public var followUpSupportRaw: String?
}

// MARK: - CDLessonAssignment DTO
/// DTO for the unified CDLessonAssignment model.
/// This model replaces LegacyPresentation + CDPresentation in the new architecture.
nonisolated struct LegacyLessonAssignmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var stateRaw: String
    public var scheduledFor: Date?
    public var presentedAt: Date?
    public var lessonID: String
    public var studentIDs: [String]
    public var lessonTitleSnapshot: String?
    public var lessonSectionSnapshot: String?
    public var needsPractice: Bool
    public var needsAnotherPresentation: Bool
    public var followUpWork: String
    public var notes: String
    public var trackID: String?
    public var trackStepID: String?
    public var migratedFromLegacyID: String?
    public var migratedFromPresentationID: String?
    /// User flag: a presentation manually unblocked despite the blocking rules. Restored so
    /// the blocking engine doesn't silently re-block it after import. Optional for
    /// compatibility with older backups that predate this field.
    public var manuallyUnblocked: Bool?
    /// Student IDs the teacher confirmed as proficient for this lesson. Restored so the blocking
    /// engine doesn't silently re-block already-cleared lessons after import. Optional for
    /// compatibility with older backups that predate this field.
    public var confirmedStudentIDs: [String]?

    public init(
        id: UUID,
        createdAt: Date,
        modifiedAt: Date,
        stateRaw: String,
        scheduledFor: Date?,
        presentedAt: Date?,
        lessonID: String,
        studentIDs: [String],
        lessonTitleSnapshot: String?,
        lessonSectionSnapshot: String?,
        needsPractice: Bool,
        needsAnotherPresentation: Bool,
        followUpWork: String,
        notes: String,
        trackID: String?,
        trackStepID: String?,
        migratedFromLegacyID: String?,
        migratedFromPresentationID: String?,
        manuallyUnblocked: Bool? = nil,
        confirmedStudentIDs: [String]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.stateRaw = stateRaw
        self.scheduledFor = scheduledFor
        self.presentedAt = presentedAt
        self.lessonID = lessonID
        self.studentIDs = studentIDs
        self.lessonTitleSnapshot = lessonTitleSnapshot
        self.lessonSectionSnapshot = lessonSectionSnapshot
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.notes = notes
        self.trackID = trackID
        self.trackStepID = trackStepID
        self.migratedFromLegacyID = migratedFromLegacyID
        self.migratedFromPresentationID = migratedFromPresentationID
        self.manuallyUnblocked = manuallyUnblocked
        self.confirmedStudentIDs = confirmedStudentIDs
    }
}

nonisolated struct LegacyNoteDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var body: String
    public var isPinned: Bool
    public var scope: String // serialized enum value
    public var tags: [String]?
    public var needsFollowUp: Bool?
    public var lessonID: UUID?
    public var workID: UUID?
    public var imagePath: String?
    // Restored fields (optional for compatibility with older backups that predate them).
    public var includeInReport: Bool?
    public var reportedBy: String?
    public var reporterName: String?
    public var communityTopicID: String?
    public var schoolDayOverrideID: String?
    public var studentTrackEnrollmentID: String?
    // FK to a Going Out (optional for compatibility with older backups that predate this field).
    public var goingOutID: String?
    // Relationship targets, relinked in a post-import pass (their entities are
    // imported in later phases, so they can't be resolved at note-import time).
    public var lessonAssignmentID: UUID?
    public var attendanceRecordID: UUID?
    public var workCheckInID: UUID?
    public var workCompletionRecordID: UUID?
    public var studentMeetingID: UUID?
    public var projectSessionID: UUID?
    public var reminderID: UUID?
    /// Retired with practice sessions (plan "Simplify the app, round two",
    /// Phase 2): read from older backups, never written, never relinked.
    public var practiceSessionID: UUID?
    public var issueID: UUID?
}

nonisolated struct LegacyNonSchoolDayDTO: Codable, Sendable {
    public var id: UUID
    public var date: Date
    public var reason: String?
}

nonisolated struct LegacySchoolDayOverrideDTO: Codable, Sendable {
    public var id: UUID
    public var date: Date
}

nonisolated struct LegacyCommunityTopicDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var issueDescription: String
    public var createdAt: Date
    public var addressedDate: Date?
    public var resolution: String
    public var raisedBy: String
    public var tags: [String]
}

nonisolated struct LegacyCommunityAttachmentDTO: Codable, Sendable {
    public var id: UUID
    public var topicID: UUID?
    public var filename: String
    public var kind: String
    // Do not include raw data; metadata only
    public var createdAt: Date
}

// MARK: - Backup/BackupTypes+Albums.swift

// Teaching-album annotations (format v21+).
//
// Note on binary data: the rest of the backup excludes binary attributes by
// design, because they are regenerable (thumbnails, covers, file bookmarks —
// see BackupTypes+V18Entities). Highlights and Pencil ink are the exception:
// nothing can recreate them, so losing them on restore would be real data
// loss. Highlight rectangles travel as plain numbers, and ink travels as its
// PencilKit drawing data.

// MARK: - Highlights and ink

nonisolated struct LegacyAlbumHighlightDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    public var lessonTitle: String
    public var text: String
    public var colorName: String
    /// Page-space rectangles as [x, y, width, height]. Decoded from the
    /// entity's JSON blob so the archive stays free of opaque binary.
    public var rects: [[Double]]
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated struct LegacyAlbumPageInkDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    /// PencilKit drawing data. Included deliberately — unlike thumbnails, ink
    /// is user-authored and cannot be regenerated.
    public var drawingData: Data
    public var modifiedAt: Date
}

// MARK: - Backup/BackupTypes+CalendarAdmin.swift

// MARK: - Calendar & Admin DTOs

nonisolated struct LegacyStudentMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var completed: Bool
    public var reflection: String
    public var focus: String
    public var requests: String
    public var guideNotes: String
}

nonisolated struct LegacyCalendarEventDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var location: String?
    public var notes: String?
    public var isAllDay: Bool
    // EventKit IDs excluded - device-specific
}

nonisolated struct LegacyScheduleSlotDTO: Codable, Sendable {
    public var id: UUID
    public var scheduleID: String
    public var studentID: String
    public var weekdayRaw: String
    public var timeString: String?
    public var sortOrder: Int
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated struct LegacyIssueDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var modifiedAt: Date
    public var title: String
    public var issueDescription: String
    public var categoryRaw: String
    public var priorityRaw: String
    public var statusRaw: String
    public var studentIDs: [String]
    public var location: String?
    public var resolvedAt: Date?
    public var resolutionSummary: String?
}

nonisolated struct LegacyIssueActionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var modifiedAt: Date
    public var issueID: String
    public var actionTypeRaw: String
    public var actionDescription: String
    public var actionDate: Date
    public var participantStudentIDs: [String]
    public var nextSteps: String?
    public var followUpRequired: Bool
    public var followUpDate: Date?
    public var followUpCompleted: Bool
}

nonisolated struct LegacyProcedureDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var content: String
    public var categoryRaw: String
    public var icon: String
    public var relatedProcedureIDs: [String]
    public var createdAt: Date
    public var modifiedAt: Date
}

// MARK: - Backup/BackupTypes+Misc.swift

// MARK: - Todo DTOs

nonisolated struct LegacyTodoItemDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var orderIndex: Int
    public var dueDate: Date?
    public var priorityRaw: String
    public var recurrenceRaw: String
    public var studentIDs: [String]
    public var linkedWorkItemID: String?
    public var attachmentPaths: [String]
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public var reminderDate: Date?
    public var reflectionNotes: String
    public var tags: [String]
    // CDSchedule fields
    public var scheduledDate: Date?
    public var isSomeday: Bool?
    public var repeatAfterCompletion: Bool?
    public var customIntervalDays: Int?
    // Location fields
    public var locationName: String?
    public var locationLatitude: Double?
    public var locationLongitude: Double?
    public var locationRadius: Double
    public var notifyOnEntry: Bool
    public var notifyOnExit: Bool
    public var moodRaw: String?
    /// The Tide action it is shared with (v41, schema 19); absent before.
    public var tideLink: String?
}

// MARK: - CDTrackEntity DTOs

nonisolated struct LegacySequenceTrackDTO: Codable, Sendable {
    public var id: UUID
    public var area: String
    public var sequence: String
    public var isSequential: Bool
    public var isExplicitlyDisabled: Bool
    public var createdAt: Date
}

// MARK: - Development Snapshot DTO

nonisolated struct LegacyDevelopmentSnapshotDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var generatedAt: Date
    public var lookbackDays: Int
    public var analysisVersion: String
    public var overallProgress: String
    public var keyStrengths: [String]
    public var areasForGrowth: [String]
    public var developmentalMilestones: [String]
    public var observedPatterns: [String]
    public var behavioralTrends: [String]
    public var socialEmotionalInsights: [String]
    public var recommendedNextLessons: [String]
    public var suggestedPracticeFocus: [String]
    public var interventionSuggestions: [String]
    public var totalNotesAnalyzed: Int
    public var practiceSessionsAnalyzed: Int
    public var workCompletionsAnalyzed: Int
    public var averagePracticeQuality: Double?
    public var independenceLevel: Double?
    public var rawAnalysisJSON: String
    public var userNotes: String
    public var isReviewed: Bool
    public var sharedWithParents: Bool
    public var sharedAt: Date?
}

// MARK: - CDSupply DTOs

nonisolated struct LegacySupplyDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryRaw: String
    public var location: String
    public var currentQuantity: Int
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
    // Restock (format v37+); absent in older backups, whose staples keep the
    // model's defaults and get levels from their counts after the restore.
    public var minimumThreshold: Int?
    public var unit: String?
    public var levelRaw: String?
    public var sourceRaw: String?
    public var urlString: String?
    public var levelChangedAt: Date?
    public var levelChangedByID: String?
    public var levelChangedByName: String?
}

// MARK: - CDDocument DTO

nonisolated struct LegacyDocumentDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var uploadDate: Date
    public var studentID: UUID?
    // PDF data excluded by design - too large for JSON backup
    /// Managed relative path only (the PDF payload itself is excluded).
    /// Optional for compatibility with older backups that predate this field.
    public var pdfFileRelativePath: String?
}

// MARK: - Agenda Order DTO

nonisolated struct LegacyTodayAgendaOrderDTO: Codable, Sendable {
    public var id: UUID
    public var day: Date
    public var itemTypeRaw: String
    public var itemID: UUID
    public var position: Int
}

// MARK: - Going Out DTOs (format v12+)

nonisolated struct LegacyGoingOutChecklistItemDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var goingOutID: String
    public var title: String
    public var isCompleted: Bool
    public var sortOrder: Int
    public var assignedToStudentID: String?
}

// MARK: - Scheduled Meeting DTO (format v12+)

nonisolated struct LegacyScheduledMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var date: Date
    public var createdAt: Date
    public var participantIDsData: Data?
    public var workID: String?
    public var isGroupMeeting: Bool?
    /// Format v24+: what the meeting is about.
    public var purpose: String?
}

// MARK: - Backup/BackupTypes+Projects.swift

// MARK: - CDProject DTOs

nonisolated struct LegacyProjectDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var bookTitle: String?
    public var memberStudentIDs: [String]
    public var isActive: Bool?
    /// Conflict-resolution timestamp, preserved so post-restore deduplication
    /// doesn't treat every restored project as "just modified". Optional for
    /// compatibility with older backups that predate this field.
    public var modifiedAt: Date?
}

nonisolated struct LegacyProjectSessionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var meetingDate: Date
    public var chapterOrPages: String?
    public var agendaItemsJSON: String
    public var templateWeekID: UUID?
    public var assignmentModeRaw: String?
    public var minSelections: Int?
    public var maxSelections: Int?
}

nonisolated struct LegacyProjectRoleDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var summary: String
    public var instructions: String
}

// MARK: - Backup/BackupTypes+V18Entities.swift

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

nonisolated struct LegacyStoryDTO: Codable, Sendable {
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

nonisolated struct LegacyBookClubPacketDTO: Codable, Sendable {
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

// MARK: - Backup/BackupTypes+Work.swift

// MARK: - Work DTOs

/// Modern DTO that captures all CDWorkModel fields (format v11+).
nonisolated struct LegacyWorkModelDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var workTypeRaw: String
    public var studentLessonID: UUID?
    public var createdAt: Date
    public var completedAt: Date?
    // Modern work tracking
    public var kindRaw: String?
    public var statusRaw: String
    public var assignedAt: Date
    public var lastTouchedAt: Date?
    public var dueAt: Date?
    public var completionOutcomeRaw: String?
    // CloudKit-compatible string FKs
    public var studentID: String
    public var lessonID: String
    public var presentationID: String?
    public var trackID: String?
    public var trackStepID: String?
    public var scheduledNote: String?
    public var scheduledReasonRaw: String?
    public var sourceContextTypeRaw: String?
    public var sourceContextID: String?
    public var sampleWorkID: String?
    public var checkInStyleRaw: String?
    // Format v14+
    public var restingUntil: Date?
}

// MARK: - CDPlanningRecommendation DTO

nonisolated struct LegacyPlanningRecommendationDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var lessonID: String
    public var studentIDsData: Data?
    public var reasoning: String
    public var confidence: Double
    public var priority: Int
    public var subjectContext: String
    public var groupContext: String
    public var planningSessionID: String
    public var depthLevel: String
    public var decisionRaw: String?
    public var decisionAt: Date?
    public var teacherNote: String?
    public var outcomeRaw: String?
    public var outcomeRecordedAt: Date?
    public var presentationID: String?
}

// MARK: - CDResource DTO

nonisolated struct LegacyResourceDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var descriptionText: String
    public var categoryRaw: String
    public var fileRelativePath: String
    public var fileSizeBytes: Int64
    public var tags: [String]
    public var isFavorite: Bool
    public var lastViewedAt: Date?
    public var linkedLessonIDs: String
    public var linkedAreas: String
    public var createdAt: Date
    public var modifiedAt: Date
    // CDNote: fileBookmark and thumbnailData are @externalStorage and excluded from backups by design
}

// MARK: - CDNoteStudentLink DTO

nonisolated struct LegacyWorkCheckInDTO: Codable, Sendable {
    public var id: UUID
    public var workID: String
    public var date: Date
    public var statusRaw: String
    public var purpose: String
    public var studentInitiated: Bool?
    /// How long the practice lasted (schema 23; absent in older backups).
    public var durationMinutes: Int?
}

nonisolated struct LegacyWorkParticipantEntityDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var completedAt: Date?
    public var workID: UUID?
}

nonisolated struct LegacyWorkCompletionRecordDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID
    public var studentID: UUID
    public var completedAt: Date
}

nonisolated struct LegacyAttendanceRecordDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var status: String
    public var absenceReason: String?
    // Attribution (optional for compatibility with backups that predate it).
    public var recordedBy: String?
    public var recordedByID: String?
    public var recordedByName: String?
    public var modifiedAt: Date?
    /// The day's shared attendance note (v29+; absent in older backups).
    public var note: String?
    /// When the current status was set (v32+; absent in older backups).
    public var markedAt: Date?
    /// When a Left Early child went home (v33+; absent in older backups).
    public var leftAt: Date?
    /// When the child is due to be picked up early (v35+; absent in older backups).
    public var leavesAt: Date?
    /// When a child who left early came back (v36+; absent in older backups).
    public var returnedAt: Date?
    /// The status a Left Early child left from (v36+; absent in older backups).
    public var statusBeforeLeavingRaw: String?

    public init(
        id: UUID,
        studentID: UUID,
        date: Date,
        status: String,
        absenceReason: String? = nil,
        recordedBy: String? = nil,
        recordedByID: String? = nil,
        recordedByName: String? = nil,
        modifiedAt: Date? = nil,
        note: String? = nil,
        markedAt: Date? = nil,
        leftAt: Date? = nil,
        leavesAt: Date? = nil,
        returnedAt: Date? = nil,
        statusBeforeLeavingRaw: String? = nil
    ) {
        self.id = id
        self.studentID = studentID
        self.date = date
        self.status = status
        self.absenceReason = absenceReason
        self.recordedBy = recordedBy
        self.recordedByID = recordedByID
        self.recordedByName = recordedByName
        self.modifiedAt = modifiedAt
        self.note = note
        self.markedAt = markedAt
        self.leftAt = leftAt
        self.leavesAt = leavesAt
        self.returnedAt = returnedAt
        self.statusBeforeLeavingRaw = statusBeforeLeavingRaw
    }
}
