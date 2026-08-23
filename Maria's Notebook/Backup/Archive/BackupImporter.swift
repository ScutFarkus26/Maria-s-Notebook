// BackupImporter.swift
// Imports a decoded v17+ backup into Core Data.
//
// The strategy: reconstruct a `BackupPayload` struct from the decoded NDJSON
// entries (off the main actor — it's pure JSON decoding), then hand it to
// `BackupService.importPayload(...)` — the single shared post-decode import
// path used by the current import flow and the internal checkpoint restore
// path. This way the entity-import dispatch, deleteAll-for-replace,
// denormalized field repair, and CloudKit-sync wait all live in one place.
//
// Any entity type that fails to decode is skipped with a warning that
// propagates into the operation summary the user sees — never silently.

import Foundation
import CoreData
import OSLog

@MainActor
enum BackupImporter {
    // nonisolated so the off-main decode path (reconstructPayload) can log.
    private nonisolated static let logger = Logger.backup

    /// Everything needed to import or preview a backup, produced off-main by
    /// `decodeArchive(at:)`.
    struct DecodedArchive: Sendable {
        let manifest: BackupArchiveManifest
        let payload: BackupPayload
        let warnings: [String]
        let encrypted: Bool
    }

    // MARK: - Public API

    /// Reads, decrypts, and JSON-decodes the archive into a typed payload.
    /// `nonisolated async` so the whole decode pipeline runs off the main
    /// actor; only the Core Data import that follows needs the main actor.
    nonisolated static func decodeArchive(at url: URL) async throws -> DecodedArchive {
        let decoded = try BackupReader.read(from: url)
        let (payload, warnings) = reconstructPayload(from: decoded)
        return DecodedArchive(
            manifest: decoded.manifest,
            payload: payload,
            warnings: warnings,
            encrypted: BackupArchive.isEncryptedArchive(at: url)
        )
    }

    /// Imports a decoded backup into the given Core Data context.
    /// Mode handling (merge/replace), deleteAll, save, CloudKit-sync-wait, and
    /// the operation summary are all owned by the underlying `importPayload`.
    /// Decode-time warnings are appended to the summary so partial decodes
    /// are visible in the UI, not just the log.
    static func importDecoded(
        _ archive: DecodedArchive,
        from fileURL: URL,
        into viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        appRouter: AppRouter,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        progress(0.35, "Importing\u{2026}")
        let service = BackupService()
        let summary = try await service.importPayload(
            payload: archive.payload,
            envelopeFormatVersion: archive.manifest.formatVersion,
            envelopeEncrypted: archive.encrypted,
            envelopeCreatedAt: archive.manifest.createdAt,
            envelopeFileName: fileURL.lastPathComponent,
            envelopeEntityCounts: archive.manifest.entityCounts,
            viewContext: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
        return archive.warnings.isEmpty ? summary : summary.appending(warnings: archive.warnings)
    }

    // MARK: - Payload Reconstruction

    /// Walks the decoded entries and decodes each one into its typed DTO
    /// array, assigning into the corresponding `BackupPayload` field.
    ///
    /// A malformed entry skips that entity type but the skip is returned as a
    /// warning for the operation summary. Unrecognized entity names are also
    /// surfaced (forward-compat: a backup made by a future app version
    /// partially imports rather than fails, but the user learns what was
    /// left behind).
    nonisolated static func reconstructPayload(
        from decoded: BackupReader.DecodedBackup
    ) -> (payload: BackupPayload, warnings: [String]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Initialize with empty arrays; we fill the ones we have entries for.
        var payload = BackupPayload(
            items: [], students: [], lessons: [],
            lessonAssignments: [],
            notes: [], nonSchoolDays: [], schoolDayOverrides: [],
            studentMeetings: [], communityTopics: [],
            proposedSolutions: [], communityAttachments: [],
            attendance: [], workCompletions: [],
            projects: [], projectAssignmentTemplates: [],
            projectSessions: [], projectRoles: [],
            projectTemplateWeeks: [], projectWeekRoleAssignments: [],
            preferences: decoded.preferences ?? PreferencesDTO(values: [:])
        )

        var warnings: [String] = []
        for entry in decoded.entries {
            guard let decodeEntry = entityDecoders[entry.entityName] else {
                let message = "Unknown entity '\(entry.entityName)' in backup \u{2014} skipped " +
                    "(likely created by a newer app version)."
                logger.warning("\(message, privacy: .public)")
                warnings.append(message)
                continue
            }
            do {
                let lines = BackupReader.ndjsonLines(in: entry)
                try decodeEntry(&payload, lines, decoder)
            } catch {
                let message = "\(entry.entityName) records could not be read from this backup " +
                    "and were skipped: \(error.localizedDescription)"
                logger.warning("\(message, privacy: .public)")
                warnings.append(message)
            }
        }

        return (payload, warnings)
    }

    // MARK: - Per-Entity Dispatch

    /// Every entity name this importer can decode. The coverage tests compare
    /// this against `BackupEntityRegistry` and `BackupWriter`.
    nonisolated static var handledEntityNames: [String] {
        Array(entityDecoders.keys)
    }

    private nonisolated static func decodeAll<T: Decodable>(
        _ type: T.Type,
        _ lines: [Data],
        _ decoder: JSONDecoder
    ) throws -> [T] {
        try lines.map { try decoder.decode(T.self, from: $0) }
    }

    /// Entity name → closure that decodes that entity's NDJSON lines into the
    /// matching `BackupPayload` field.
    private nonisolated static let entityDecoders: [String: @Sendable (
        inout BackupPayload, [Data], JSONDecoder
    ) throws -> Void] = [
        // Core (required)
        "Student": { $0.students = try decodeAll(StudentDTO.self, $1, $2) },
        "Lesson": { $0.lessons = try decodeAll(LessonDTO.self, $1, $2) },
        "LessonAssignment": { $0.lessonAssignments = try decodeAll(LessonAssignmentDTO.self, $1, $2) },
        "Note": { $0.notes = try decodeAll(NoteDTO.self, $1, $2) },
        "NonSchoolDay": { $0.nonSchoolDays = try decodeAll(NonSchoolDayDTO.self, $1, $2) },
        "SchoolDayOverride": { $0.schoolDayOverrides = try decodeAll(SchoolDayOverrideDTO.self, $1, $2) },
        "StudentMeeting": { $0.studentMeetings = try decodeAll(StudentMeetingDTO.self, $1, $2) },
        "CommunityTopic": { $0.communityTopics = try decodeAll(CommunityTopicDTO.self, $1, $2) },
        "ProposedSolution": { $0.proposedSolutions = try decodeAll(ProposedSolutionDTO.self, $1, $2) },
        "CommunityAttachment": { $0.communityAttachments = try decodeAll(CommunityAttachmentDTO.self, $1, $2) },
        "AttendanceRecord": { $0.attendance = try decodeAll(AttendanceRecordDTO.self, $1, $2) },
        "WorkCompletionRecord": { $0.workCompletions = try decodeAll(WorkCompletionRecordDTO.self, $1, $2) },
        "Project": { $0.projects = try decodeAll(ProjectDTO.self, $1, $2) },
        "ProjectSession": { $0.projectSessions = try decodeAll(ProjectSessionDTO.self, $1, $2) },
        "ProjectRole": { $0.projectRoles = try decodeAll(ProjectRoleDTO.self, $1, $2) },

        // Optional v8+ extensions
        "WorkModel": { $0.workModels = try decodeAll(WorkModelDTO.self, $1, $2) },
        "WorkCheckIn": { $0.workCheckIns = try decodeAll(WorkCheckInDTO.self, $1, $2) },
        "WorkStep": { $0.workSteps = try decodeAll(WorkStepDTO.self, $1, $2) },
        "WorkParticipantEntity": { $0.workParticipants = try decodeAll(WorkParticipantEntityDTO.self, $1, $2) },
        "PracticeSession": { $0.practiceSessions = try decodeAll(PracticeSessionDTO.self, $1, $2) },
        "LessonAttachment": { $0.lessonAttachments = try decodeAll(LessonAttachmentDTO.self, $1, $2) },
        "LessonPresentation": { $0.lessonPresentations = try decodeAll(LessonPresentationDTO.self, $1, $2) },
        "LessonRecallCheck": { $0.recallChecks = try decodeAll(LessonRecallCheckDTO.self, $1, $2) },
        "SampleWork": { $0.sampleWorks = try decodeAll(SampleWorkDTO.self, $1, $2) },
        "SampleWorkStep": { $0.sampleWorkSteps = try decodeAll(SampleWorkStepDTO.self, $1, $2) },
        "NoteTemplate": { $0.noteTemplates = try decodeAll(NoteTemplateDTO.self, $1, $2) },
        "MeetingTemplate": { $0.meetingTemplates = try decodeAll(MeetingTemplateDTO.self, $1, $2) },
        "Reminder": { $0.reminders = try decodeAll(ReminderDTO.self, $1, $2) },
        "CalendarEvent": { $0.calendarEvents = try decodeAll(CalendarEventDTO.self, $1, $2) },
        "Track": { $0.tracks = try decodeAll(TrackDTO.self, $1, $2) },
        "TrackStep": { $0.trackSteps = try decodeAll(TrackStepDTO.self, $1, $2) },
        "StudentTrackEnrollment": {
            $0.studentTrackEnrollments = try decodeAll(StudentTrackEnrollmentDTO.self, $1, $2)
        },
        "SequenceTrack": { $0.sequenceTracks = try decodeAll(SequenceTrackDTO.self, $1, $2) },
        "Document": { $0.documents = try decodeAll(DocumentDTO.self, $1, $2) },
        "Supply": { $0.supplies = try decodeAll(SupplyDTO.self, $1, $2) },
        "Procedure": { $0.procedures = try decodeAll(ProcedureDTO.self, $1, $2) },
        "Schedule": { $0.schedules = try decodeAll(ScheduleDTO.self, $1, $2) },
        "ScheduleSlot": { $0.scheduleSlots = try decodeAll(ScheduleSlotDTO.self, $1, $2) },
        "Issue": { $0.issues = try decodeAll(IssueDTO.self, $1, $2) },
        "IssueAction": { $0.issueActions = try decodeAll(IssueActionDTO.self, $1, $2) },
        "DevelopmentSnapshot": {
            $0.developmentSnapshots = try decodeAll(DevelopmentSnapshotDTO.self, $1, $2)
        },
        "TodoItem": { $0.todoItems = try decodeAll(TodoItemDTO.self, $1, $2) },
        "TodoSubtask": { $0.todoSubtasks = try decodeAll(TodoSubtaskDTO.self, $1, $2) },
        "TodoTemplate": { $0.todoTemplates = try decodeAll(TodoTemplateDTO.self, $1, $2) },
        "TodayAgendaOrder": { $0.todayAgendaOrders = try decodeAll(TodayAgendaOrderDTO.self, $1, $2) },
        "PlanningRecommendation": {
            $0.planningRecommendations = try decodeAll(PlanningRecommendationDTO.self, $1, $2)
        },
        "Resource": { $0.resources = try decodeAll(ResourceDTO.self, $1, $2) },
        "NoteStudentLink": { $0.noteStudentLinks = try decodeAll(NoteStudentLinkDTO.self, $1, $2) },
        "GoingOut": { $0.goingOuts = try decodeAll(GoingOutDTO.self, $1, $2) },
        "GoingOutChecklistItem": {
            $0.goingOutChecklistItems = try decodeAll(GoingOutChecklistItemDTO.self, $1, $2)
        },
        "ClassroomJob": { $0.classroomJobs = try decodeAll(ClassroomJobDTO.self, $1, $2) },
        "JobAssignment": { $0.jobAssignments = try decodeAll(JobAssignmentDTO.self, $1, $2) },
        "CalendarNote": { $0.calendarNotes = try decodeAll(CalendarNoteDTO.self, $1, $2) },
        "ScheduledMeeting": { $0.scheduledMeetings = try decodeAll(ScheduledMeetingDTO.self, $1, $2) },
        "ClassroomMembership": { $0.classroomMemberships = try decodeAll(ClassroomMembershipDTO.self, $1, $2) },
        "MeetingWorkReview": { $0.meetingWorkReviews = try decodeAll(MeetingWorkReviewDTO.self, $1, $2) },
        "StudentFocusItem": { $0.studentFocusItems = try decodeAll(StudentFocusItemDTO.self, $1, $2) },

        // Format v18+ extensions
        "DayPad": { $0.dayPads = try decodeAll(DayPadDTO.self, $1, $2) },
        "YearPlanEntry": { $0.yearPlanEntries = try decodeAll(YearPlanEntryDTO.self, $1, $2) },
        "LessonSequenceSettings": {
            $0.lessonSequenceSettings = try decodeAll(LessonSequenceSettingsDTO.self, $1, $2)
        },
        "Story": { $0.stories = try decodeAll(StoryDTO.self, $1, $2) },
        "BookClubPacket": { $0.bookClubPackets = try decodeAll(BookClubPacketDTO.self, $1, $2) },
        "BookClubSession": { $0.bookClubSessions = try decodeAll(BookClubSessionDTO.self, $1, $2) },
        "BookClubMeeting": { $0.bookClubMeetings = try decodeAll(BookClubMeetingDTO.self, $1, $2) },

        // Format v20+ extensions
        "Guardian": { $0.guardians = try decodeAll(GuardianDTO.self, $1, $2) },
        "ParentCommunication": {
            $0.parentCommunications = try decodeAll(ParentCommunicationDTO.self, $1, $2)
        },

        // Format v21+ extensions — teaching-album annotations
        "AlbumBookmark": { $0.albumBookmarks = try decodeAll(AlbumBookmarkDTO.self, $1, $2) },
        "AlbumPageNote": { $0.albumPageNotes = try decodeAll(AlbumPageNoteDTO.self, $1, $2) },
        "AlbumRecentVisit": {
            $0.albumRecentVisits = try decodeAll(AlbumRecentVisitDTO.self, $1, $2)
        },
        "AlbumReadingPosition": {
            $0.albumReadingPositions = try decodeAll(AlbumReadingPositionDTO.self, $1, $2)
        },
        "AlbumHighlight": { $0.albumHighlights = try decodeAll(AlbumHighlightDTO.self, $1, $2) },
        "AlbumPageInk": { $0.albumPageInk = try decodeAll(AlbumPageInkDTO.self, $1, $2) }
    ]
}
