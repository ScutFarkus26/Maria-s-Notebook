import CoreData
import Foundation
@testable import CosmicDaybook

// `BackupService.collectPayload` as it stood before the export streamed one
// entity type at a time (2026-09-26), copied verbatim — only the entry point is
// renamed, and `collectOrderDTOs` (then in BackupDTOTransformers+Orders.swift)
// is carried along. The streaming tests compare the new collector table and the
// streamed archive against it, so do not "fix" or modernise this code: its only
// job is to be the old code.

extension BackupService {

    /// The pre-2026-09-26 `collectPayload`, renamed.
    func legacyCollectPayload(
        viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback = { _, _ in }
    ) -> BackupPayload {
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
            preferences: buildPreferencesDTO()
        )

        collectCoreEntityDTOs(into: &payload, using: viewContext, progress: progress)
        collectRelationAndProjectDTOs(into: &payload, using: viewContext, progress: progress)
        collectWorkTrackingDTOs(into: &payload, using: viewContext, progress: progress)
        collectTemplateAndTrackDTOs(into: &payload, using: viewContext, progress: progress)
        collectOrganizationDTOs(into: &payload, using: viewContext, progress: progress)
        collectV18DTOs(into: &payload, using: viewContext, progress: progress)
        collectV20DTOs(into: &payload, using: viewContext, progress: progress)
        collectV21DTOs(into: &payload, using: viewContext, progress: progress)
        collectOrderDTOs(into: &payload, using: viewContext)

        return payload
    }

    // MARK: - DTO Collection Helpers

    private func collectCoreEntityDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students\u{2026}")
        payload.students = fetchAndTransformInBatches(
            CDStudent.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons\u{2026}")
        payload.lessons = fetchAndTransformInBatches(
            CDLesson.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.15), "Collecting lesson assignments\u{2026}")
        payload.lessonAssignments = fetchAndTransformInBatches(
            CDLessonAssignment.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.24), "Collecting notes\u{2026}")
        payload.notes = fetchAndTransformInBatches(
            CDNote.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.27), "Collecting calendar data\u{2026}")
        payload.nonSchoolDays = fetchAndTransformInBatches(
            CDNonSchoolDay.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.schoolDayOverrides = fetchAndTransformInBatches(
            CDSchoolDayOverride.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
    }

    private func collectRelationAndProjectDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings\u{2026}")
        payload.studentMeetings = fetchAndTransformInBatches(
            CDStudentMeeting.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data\u{2026}")
        payload.communityTopics = fetchAndTransformInBatches(
            CDCommunityTopicEntity.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.proposedSolutions = fetchAndTransformInBatches(
            CDProposedSolutionEntity.self, using: viewContext) { ProposedSolutionDTO.rows($0) }
        payload.communityAttachments = fetchAndTransformInBatches(
            CDCommunityAttachment.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.36),
            "Collecting attendance and work completions\u{2026}"
        )
        payload.attendance = fetchAndTransformInBatches(
            CDAttendanceRecord.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.workCompletions = fetchAndTransformInBatches(
            CDWorkCompletionRecord.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.39), "Collecting projects\u{2026}")
        payload.projects = fetchAndTransformInBatches(
            CDProject.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectAssignmentTemplates = [] // Deprecated
        payload.projectSessions = fetchAndTransformInBatches(
            CDProjectSession.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectRoles = fetchAndTransformInBatches(
            CDProjectRole.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectTemplateWeeks = [] // Deprecated
        payload.projectWeekRoleAssignments = [] // Deprecated
    }

    private func collectWorkTrackingDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.42), "Collecting work tracking\u{2026}")
        payload.workModels = fetchAndTransformInBatches(
            CDWorkModel.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workCheckIns = fetchAndTransformInBatches(
            CDWorkCheckIn.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workSteps = fetchAndTransformInBatches(
            CDWorkStep.self, using: viewContext) { WorkStepDTO.rows($0) }
        payload.workParticipants = fetchAndTransformInBatches(
            CDWorkParticipantEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.practiceSessions = fetchAndTransformInBatches(
            CDPracticeSession.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.50), "Collecting lesson extras\u{2026}")
        payload.lessonAttachments = fetchAndTransformInBatches(
            CDLessonAttachment.self, using: viewContext) { LessonAttachmentDTO.rows($0) }
        payload.lessonPresentations = fetchAndTransformInBatches(
            CDLessonPresentation.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.recallChecks = fetchAndTransformInBatches(
            CDLessonRecallCheck.self, using: viewContext) { LessonRecallCheckDTO.rows($0) }
        payload.sampleWorks = fetchAndTransformInBatches(
            CDSampleWork.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.sampleWorkSteps = fetchAndTransformInBatches(
            CDSampleWorkStep.self, using: viewContext) { SampleWorkStepDTO.rows($0) }
    }

    private func collectTemplateAndTrackDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.55), "Collecting templates & tracks\u{2026}")
        payload.noteTemplates = fetchAndTransformInBatches(
            CDNoteTemplate.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.meetingTemplates = fetchAndTransformInBatches(
            CDMeetingTemplate.self, using: viewContext) { MeetingTemplateDTO.rows($0) }
        payload.reminders = fetchAndTransformInBatches(
            CDReminder.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.calendarEvents = fetchAndTransformInBatches(
            CDCalendarEvent.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.tracks = fetchAndTransformInBatches(
            CDTrackEntity.self, using: viewContext) { TrackDTO.rows($0) }
        payload.trackSteps = fetchAndTransformInBatches(
            CDTrackStep.self, using: viewContext) { TrackStepDTO.rows($0) }
        payload.studentTrackEnrollments = fetchAndTransformInBatches(
            CDStudentTrackEnrollmentEntity.self, using: viewContext) { StudentTrackEnrollmentDTO.rows($0) }
        payload.sequenceTracks = fetchAndTransformInBatches(
            CDSequenceTrack.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    // swiftlint:disable:next function_body_length
    private func collectOrganizationDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.65),
            "Collecting supplies, schedules & issues\u{2026}"
        )
        payload.documents = fetchAndTransformInBatches(
            CDDocument.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.supplies = fetchAndTransformInBatches(
            CDSupply.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.procedures = fetchAndTransformInBatches(
            CDProcedure.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.schedules = fetchAndTransformInBatches(
            CDSchedule.self, using: viewContext) { ScheduleDTO.rows($0) }
        payload.scheduleSlots = fetchAndTransformInBatches(
            CDScheduleSlot.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.issues = fetchAndTransformInBatches(
            CDIssue.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.issueActions = fetchAndTransformInBatches(
            CDIssueAction.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.75), "Collecting snapshots & todos\u{2026}")
        payload.developmentSnapshots = fetchAndTransformInBatches(
            CDDevelopmentSnapshotEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoItems = fetchAndTransformInBatches(
            CDTodoItem.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoSubtasks = fetchAndTransformInBatches(
            CDTodoSubtask.self, using: viewContext) { TodoSubtaskDTO.rows($0) }
        payload.todoTemplates = fetchAndTransformInBatches(
            CDTodoTemplate.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todayAgendaOrders = fetchAndTransformInBatches(
            CDTodayAgendaOrder.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.80),
            "Collecting recommendations & resources\u{2026}"
        )
        payload.planningRecommendations = fetchAndTransformInBatches(
            CDPlanningRecommendation.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.resources = fetchAndTransformInBatches(
            CDResource.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.noteStudentLinks = fetchAndTransformInBatches(
            CDNoteStudentLink.self, using: viewContext) { NoteStudentLinkDTO.rows($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.85),
            "Collecting going-outs, jobs & transitions\u{2026}"
        )
        payload.goingOuts = fetchAndTransformInBatches(
            CDGoingOut.self, using: viewContext) { GoingOutDTO.rows($0) }
        payload.goingOutChecklistItems = fetchAndTransformInBatches(
            CDGoingOutChecklistItem.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.classroomJobs = fetchAndTransformInBatches(
            CDClassroomJob.self, using: viewContext) { ClassroomJobDTO.rows($0) }
        payload.jobAssignments = fetchAndTransformInBatches(
            CDJobAssignment.self, using: viewContext) { JobAssignmentDTO.rows($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.90),
            "Collecting calendar notes & meetings\u{2026}"
        )
        payload.calendarNotes = fetchAndTransformInBatches(
            CDCalendarNote.self, using: viewContext) { CalendarNoteDTO.rows($0) }
        payload.scheduledMeetings = fetchAndTransformInBatches(
            CDScheduledMeeting.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.93),
            "Collecting classroom memberships\u{2026}"
        )
        payload.classroomMemberships = fetchAndTransformInBatches(
            CDClassroomMembership.self, using: viewContext) { ClassroomMembershipDTO.rows($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.95),
            "Collecting meeting work reviews & focus items\u{2026}"
        )
        payload.meetingWorkReviews = fetchAndTransformInBatches(
            CDMeetingWorkReview.self, using: viewContext) { MeetingWorkReviewDTO.rows($0) }
        payload.studentFocusItems = fetchAndTransformInBatches(
            CDStudentFocusItem.self, using: viewContext) { StudentFocusItemDTO.rows($0) }
    }

    /// Collects the format v18 entity types: Stories, Book Club, Year Plan,
    /// Lesson Sequence Settings, and Day Pads.
    private func collectV18DTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.97),
            "Collecting stories, book club & year plan\u{2026}"
        )
        payload.dayPads = fetchAndTransformInBatches(
            CDDayPad.self, using: viewContext) { DayPadDTO.rows($0) }
        payload.yearPlanEntries = fetchAndTransformInBatches(
            CDYearPlanEntry.self, using: viewContext) { YearPlanEntryDTO.rows($0) }
        payload.lessonSequenceSettings = fetchAndTransformInBatches(
            CDLessonSequenceSettings.self, using: viewContext) { LessonSequenceSettingsDTO.rows($0) }
        payload.stories = fetchAndTransformInBatches(
            CDStory.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.bookClubPackets = fetchAndTransformInBatches(
            CDBookClubPacket.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.bookClubSessions = fetchAndTransformInBatches(
            CDBookClubSession.self, using: viewContext) { BookClubSessionDTO.rows($0) }
        payload.bookClubMeetings = fetchAndTransformInBatches(
            CDBookClubMeeting.self, using: viewContext) { BookClubMeetingDTO.rows($0) }
    }

    /// Collects the format v20 entity types: Guardians and Parent Communications.
    private func collectV20DTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.98),
            "Collecting guardians & parent communications\u{2026}"
        )
        payload.guardians = fetchAndTransformInBatches(
            CDGuardian.self, using: viewContext) { GuardianDTO.rows($0) }
        payload.parentCommunications = fetchAndTransformInBatches(
            CDParentCommunication.self, using: viewContext) { ParentCommunicationDTO.rows($0) }
    }

    /// Collects the format v21 entity types: teaching-album annotations.
    private func collectV21DTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.99),
            "Collecting album bookmarks & notes\u{2026}"
        )
        payload.albumBookmarks = fetchAndTransformInBatches(
            CDAlbumBookmark.self, using: viewContext) { AlbumBookmarkDTO.rows($0) }
        payload.albumPageNotes = fetchAndTransformInBatches(
            CDAlbumPageNote.self, using: viewContext) { AlbumPageNoteDTO.rows($0) }
        payload.albumRecentVisits = fetchAndTransformInBatches(
            CDAlbumRecentVisit.self, using: viewContext) { AlbumRecentVisitDTO.rows($0) }
        payload.albumReadingPositions = fetchAndTransformInBatches(
            CDAlbumReadingPosition.self, using: viewContext) { AlbumReadingPositionDTO.rows($0) }
        payload.albumHighlights = fetchAndTransformInBatches(
            CDAlbumHighlight.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.albumPageInk = fetchAndTransformInBatches(
            CDAlbumPageInk.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    /// Collects the format v27 entity type: Orders. Lives here rather than in
    /// BackupService+DataCollection, which is at SwiftLint's file-length limit.
    func collectOrderDTOs(into payload: inout BackupPayload, using viewContext: NSManagedObjectContext) {
        payload.orderItems = fetchAndTransformInBatches(
            CDOrderItem.self, using: viewContext) { OrderItemDTO.rows($0) }
    }
}
