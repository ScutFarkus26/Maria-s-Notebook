// BackupImporter.swift
// Imports a decoded v17 AEA backup into Core Data.
//
// The strategy: reconstruct a legacy `BackupPayload` struct from the
// decoded NDJSON entries, then hand it to `BackupService.importPayload(...)` —
// the single shared post-decode import path used by both v5–v16 and v17 flows.
// This way the entity-import dispatch, deleteAll-for-replace, denormalized
// field repair, and CloudKit-sync wait all live in one place.

import Foundation
import CoreData
import OSLog

@MainActor
enum BackupImporter {
    private static let logger = Logger.backup

    // MARK: - Public API

    /// Imports a decoded v17 backup into the given Core Data context.
    /// Mode handling (merge/replace), deleteAll, save, CloudKit-sync-wait, and
    /// the operation summary are all owned by the underlying `importPayload`.
    static func importDecoded(
        _ decoded: BackupReader.DecodedBackup,
        from fileURL: URL,
        into viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        appRouter: AppRouter,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        progress(0.30, "Reconstructing payload\u{2026}")
        let payload = try reconstructPayload(from: decoded)

        progress(0.35, "Importing\u{2026}")
        let service = BackupService()
        return try await service.importPayload(
            payload: payload,
            envelopeFormatVersion: decoded.manifest.formatVersion,
            envelopeEncrypted: false,
            envelopeCreatedAt: decoded.manifest.createdAt,
            envelopeFileName: fileURL.lastPathComponent,
            envelopeEntityCounts: decoded.manifest.entityCounts,
            viewContext: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
    }

    // MARK: - Payload Reconstruction

    /// Walks the decoded entries and decodes each one into its typed DTO array,
    /// assigning into the corresponding `BackupPayload` field. Entries whose
    /// entityName isn't recognized are logged and skipped (forward-compat with
    /// future format versions that add new entity types).
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func reconstructPayload(
        from decoded: BackupReader.DecodedBackup
    ) throws -> BackupPayload {
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

        for entry in decoded.entries {
            let lines = BackupReader.ndjsonLines(in: entry)
            do {
                try assign(
                    entityName: entry.entityName,
                    lines: lines,
                    decoder: decoder,
                    into: &payload
                )
            } catch {
                logger.warning(
                    "Skipping malformed entries for \(entry.entityName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return payload
    }

    // MARK: - Per-Entity Dispatch

    /// Decodes `lines` as `[DTO]` and assigns into the right `payload` field.
    /// Unknown entity names are logged (forward-compat) — not thrown — so a
    /// backup made by a future app version partially imports rather than fails.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func assign(
        entityName: String,
        lines: [Data],
        decoder: JSONDecoder,
        into payload: inout BackupPayload
    ) throws {
        switch entityName {
        // Core (required)
        case "Student":
            payload.students = try lines.map { try decoder.decode(StudentDTO.self, from: $0) }
        case "Lesson":
            payload.lessons = try lines.map { try decoder.decode(LessonDTO.self, from: $0) }
        case "LessonAssignment":
            payload.lessonAssignments = try lines.map { try decoder.decode(LessonAssignmentDTO.self, from: $0) }
        case "Note":
            payload.notes = try lines.map { try decoder.decode(NoteDTO.self, from: $0) }
        case "NonSchoolDay":
            payload.nonSchoolDays = try lines.map { try decoder.decode(NonSchoolDayDTO.self, from: $0) }
        case "SchoolDayOverride":
            payload.schoolDayOverrides = try lines.map { try decoder.decode(SchoolDayOverrideDTO.self, from: $0) }
        case "StudentMeeting":
            payload.studentMeetings = try lines.map { try decoder.decode(StudentMeetingDTO.self, from: $0) }
        case "CommunityTopic":
            payload.communityTopics = try lines.map { try decoder.decode(CommunityTopicDTO.self, from: $0) }
        case "ProposedSolution":
            payload.proposedSolutions = try lines.map { try decoder.decode(ProposedSolutionDTO.self, from: $0) }
        case "CommunityAttachment":
            payload.communityAttachments = try lines.map { try decoder.decode(CommunityAttachmentDTO.self, from: $0) }
        case "AttendanceRecord":
            payload.attendance = try lines.map { try decoder.decode(AttendanceRecordDTO.self, from: $0) }
        case "WorkCompletionRecord":
            payload.workCompletions = try lines.map { try decoder.decode(WorkCompletionRecordDTO.self, from: $0) }
        case "Project":
            payload.projects = try lines.map { try decoder.decode(ProjectDTO.self, from: $0) }
        case "ProjectSession":
            payload.projectSessions = try lines.map { try decoder.decode(ProjectSessionDTO.self, from: $0) }
        case "ProjectRole":
            payload.projectRoles = try lines.map { try decoder.decode(ProjectRoleDTO.self, from: $0) }

        // Optional v8+ extensions
        case "WorkModel":
            payload.workModels = try lines.map { try decoder.decode(WorkModelDTO.self, from: $0) }
        case "WorkCheckIn":
            payload.workCheckIns = try lines.map { try decoder.decode(WorkCheckInDTO.self, from: $0) }
        case "WorkStep":
            payload.workSteps = try lines.map { try decoder.decode(WorkStepDTO.self, from: $0) }
        case "WorkParticipantEntity":
            payload.workParticipants = try lines.map { try decoder.decode(WorkParticipantEntityDTO.self, from: $0) }
        case "PracticeSession":
            payload.practiceSessions = try lines.map { try decoder.decode(PracticeSessionDTO.self, from: $0) }
        case "LessonAttachment":
            payload.lessonAttachments = try lines.map { try decoder.decode(LessonAttachmentDTO.self, from: $0) }
        case "LessonPresentation":
            payload.lessonPresentations = try lines.map { try decoder.decode(LessonPresentationDTO.self, from: $0) }
        case "SampleWork":
            payload.sampleWorks = try lines.map { try decoder.decode(SampleWorkDTO.self, from: $0) }
        case "SampleWorkStep":
            payload.sampleWorkSteps = try lines.map { try decoder.decode(SampleWorkStepDTO.self, from: $0) }
        case "NoteTemplate":
            payload.noteTemplates = try lines.map { try decoder.decode(NoteTemplateDTO.self, from: $0) }
        case "MeetingTemplate":
            payload.meetingTemplates = try lines.map { try decoder.decode(MeetingTemplateDTO.self, from: $0) }
        case "Reminder":
            payload.reminders = try lines.map { try decoder.decode(ReminderDTO.self, from: $0) }
        case "CalendarEvent":
            payload.calendarEvents = try lines.map { try decoder.decode(CalendarEventDTO.self, from: $0) }
        case "Track":
            payload.tracks = try lines.map { try decoder.decode(TrackDTO.self, from: $0) }
        case "TrackStep":
            payload.trackSteps = try lines.map { try decoder.decode(TrackStepDTO.self, from: $0) }
        case "StudentTrackEnrollment":
            payload.studentTrackEnrollments = try lines.map { try decoder.decode(StudentTrackEnrollmentDTO.self, from: $0) }
        case "SequenceTrack":
            payload.sequenceTracks = try lines.map { try decoder.decode(SequenceTrackDTO.self, from: $0) }
        case "Document":
            payload.documents = try lines.map { try decoder.decode(DocumentDTO.self, from: $0) }
        case "Supply":
            payload.supplies = try lines.map { try decoder.decode(SupplyDTO.self, from: $0) }
        case "Procedure":
            payload.procedures = try lines.map { try decoder.decode(ProcedureDTO.self, from: $0) }
        case "Schedule":
            payload.schedules = try lines.map { try decoder.decode(ScheduleDTO.self, from: $0) }
        case "ScheduleSlot":
            payload.scheduleSlots = try lines.map { try decoder.decode(ScheduleSlotDTO.self, from: $0) }
        case "Issue":
            payload.issues = try lines.map { try decoder.decode(IssueDTO.self, from: $0) }
        case "IssueAction":
            payload.issueActions = try lines.map { try decoder.decode(IssueActionDTO.self, from: $0) }
        case "DevelopmentSnapshot":
            payload.developmentSnapshots = try lines.map { try decoder.decode(DevelopmentSnapshotDTO.self, from: $0) }
        case "TodoItem":
            payload.todoItems = try lines.map { try decoder.decode(TodoItemDTO.self, from: $0) }
        case "TodoSubtask":
            payload.todoSubtasks = try lines.map { try decoder.decode(TodoSubtaskDTO.self, from: $0) }
        case "TodoTemplate":
            payload.todoTemplates = try lines.map { try decoder.decode(TodoTemplateDTO.self, from: $0) }
        case "TodayAgendaOrder":
            payload.todayAgendaOrders = try lines.map { try decoder.decode(TodayAgendaOrderDTO.self, from: $0) }
        case "PlanningRecommendation":
            payload.planningRecommendations = try lines.map { try decoder.decode(PlanningRecommendationDTO.self, from: $0) }
        case "Resource":
            payload.resources = try lines.map { try decoder.decode(ResourceDTO.self, from: $0) }
        case "NoteStudentLink":
            payload.noteStudentLinks = try lines.map { try decoder.decode(NoteStudentLinkDTO.self, from: $0) }
        case "GoingOut":
            payload.goingOuts = try lines.map { try decoder.decode(GoingOutDTO.self, from: $0) }
        case "GoingOutChecklistItem":
            payload.goingOutChecklistItems = try lines.map { try decoder.decode(GoingOutChecklistItemDTO.self, from: $0) }
        case "ClassroomJob":
            payload.classroomJobs = try lines.map { try decoder.decode(ClassroomJobDTO.self, from: $0) }
        case "JobAssignment":
            payload.jobAssignments = try lines.map { try decoder.decode(JobAssignmentDTO.self, from: $0) }
        case "TransitionPlan":
            payload.transitionPlans = try lines.map { try decoder.decode(TransitionPlanDTO.self, from: $0) }
        case "TransitionChecklistItem":
            payload.transitionChecklistItems = try lines.map { try decoder.decode(TransitionChecklistItemDTO.self, from: $0) }
        case "CalendarNote":
            payload.calendarNotes = try lines.map { try decoder.decode(CalendarNoteDTO.self, from: $0) }
        case "ScheduledMeeting":
            payload.scheduledMeetings = try lines.map { try decoder.decode(ScheduledMeetingDTO.self, from: $0) }
        case "ClassroomMembership":
            payload.classroomMemberships = try lines.map { try decoder.decode(ClassroomMembershipDTO.self, from: $0) }
        case "MeetingWorkReview":
            payload.meetingWorkReviews = try lines.map { try decoder.decode(MeetingWorkReviewDTO.self, from: $0) }
        case "StudentFocusItem":
            payload.studentFocusItems = try lines.map { try decoder.decode(StudentFocusItemDTO.self, from: $0) }

        default:
            logger.warning("Unknown entity '\(entityName, privacy: .public)' in backup — skipped (likely a newer format version)")
        }
    }
}
