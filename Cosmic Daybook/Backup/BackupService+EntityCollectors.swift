// BackupService+EntityCollectors.swift
// The export's collection step, one backed-up entity type per row.
//
// `collectPayload` runs every row into one payload. The streamed export
// (`BackupWriter+Streaming`) runs them one at a time and encodes each type
// before collecting the next, so only one type's DTOs are alive at once.
// Both paths read this table, so they fetch the same rows through the same
// transformers in the same order. Rows are in archive order — the order of
// `BackupWriter.entitySerializations`, which `BackupStreamingExportTests` pins.

import CoreData
import Foundation

extension BackupService {

    /// A progress line reported just before one entity type is collected: a
    /// sub-progress within `BackupProgress.Phase.collecting` and its message.
    struct CollectionAnnouncement: Sendable {
        let fraction: Double
        let message: String

        init(_ fraction: Double, _ message: String) {
            self.fraction = fraction
            self.message = message
        }
    }

    /// Collects one backed-up entity type: every row, fetched from the view
    /// context in batches (`fetchAndTransformInBatches`) and stored as DTOs in
    /// the matching `BackupPayload` field.
    struct EntityCollector {
        /// The archive entity name ("Student", "WorkParticipantEntity", …).
        let entityName: String
        let announcement: CollectionAnnouncement?
        let collect: @MainActor (BackupService, NSManagedObjectContext, inout BackupPayload) -> Void

        /// A row for one of the payload's always-present arrays.
        static func required<Object: NSManagedObject, DTO>(
            _ entityName: String,
            _ type: Object.Type,
            _ field: WritableKeyPath<BackupPayload, [DTO]> & Sendable,
            _ transform: @escaping @MainActor ([Object]) -> [DTO],
            announcing announcement: CollectionAnnouncement? = nil
        ) -> EntityCollector {
            EntityCollector(entityName: entityName, announcement: announcement) { service, context, payload in
                payload[keyPath: field] = service.fetchAndTransformInBatches(type, using: context, transform: transform)
            }
        }

        /// A row for one of the payload's later-format (optional) arrays. The
        /// collector always stores an array, empty or not, never `nil`.
        static func optional<Object: NSManagedObject, DTO>(
            _ entityName: String,
            _ type: Object.Type,
            _ field: WritableKeyPath<BackupPayload, [DTO]?> & Sendable,
            _ transform: @escaping @MainActor ([Object]) -> [DTO],
            announcing announcement: CollectionAnnouncement? = nil
        ) -> EntityCollector {
            EntityCollector(entityName: entityName, announcement: announcement) { service, context, payload in
                payload[keyPath: field] = service.fetchAndTransformInBatches(type, using: context, transform: transform)
            }
        }
    }

    /// Every backed-up entity type, in archive order. Split into groups only to
    /// keep each array literal quick to type-check.
    static let entityCollectors: [EntityCollector] =
        coreCollectors + workAndLessonCollectors + templateAndTrackCollectors
            + organizationCollectors + laterFormatCollectors

    // MARK: - Groups

    private static let coreCollectors: [EntityCollector] = [
        .required(
            "Student", CDStudent.self, \.students, BackupServiceHelpers.toDTOs,
            announcing: .init(0.0, "Collecting students\u{2026}")
        ),
        .required(
            "Lesson", CDLesson.self, \.lessons, BackupServiceHelpers.toDTOs,
            announcing: .init(0.06, "Collecting lessons\u{2026}")
        ),
        .required(
            "LessonAssignment", CDLessonAssignment.self, \.lessonAssignments, BackupDTOTransformers.toDTOs,
            announcing: .init(0.15, "Collecting lesson assignments\u{2026}")
        ),
        .required(
            "Note", CDNote.self, \.notes, BackupServiceHelpers.toDTOs,
            announcing: .init(0.24, "Collecting notes\u{2026}")
        ),
        .required(
            "NonSchoolDay", CDNonSchoolDay.self, \.nonSchoolDays, BackupServiceHelpers.toDTOs,
            announcing: .init(0.27, "Collecting calendar data\u{2026}")
        ),
        .required("SchoolDayOverride", CDSchoolDayOverride.self, \.schoolDayOverrides, BackupServiceHelpers.toDTOs),
        .required(
            "StudentMeeting", CDStudentMeeting.self, \.studentMeetings, BackupServiceHelpers.toDTOs,
            announcing: .init(0.30, "Collecting meetings\u{2026}")
        ),
        .required(
            "CommunityTopic", CDCommunityTopicEntity.self, \.communityTopics, BackupServiceHelpers.toDTOs,
            announcing: .init(0.33, "Collecting community data\u{2026}")
        ),
        .required(
            "ProposedSolution", CDProposedSolutionEntity.self, \.proposedSolutions, BackupServiceHelpers.toDTOs
        ),
        .required(
            "CommunityAttachment", CDCommunityAttachment.self, \.communityAttachments, BackupServiceHelpers.toDTOs
        ),
        .required(
            "AttendanceRecord", CDAttendanceRecord.self, \.attendance, BackupServiceHelpers.toDTOs,
            announcing: .init(0.36, "Collecting attendance and work completions\u{2026}")
        ),
        .required(
            "WorkCompletionRecord", CDWorkCompletionRecord.self, \.workCompletions, BackupServiceHelpers.toDTOs
        ),
        .required(
            "Project", CDProject.self, \.projects, BackupServiceHelpers.toDTOs,
            announcing: .init(0.39, "Collecting projects\u{2026}")
        ),
        .required("ProjectSession", CDProjectSession.self, \.projectSessions, BackupServiceHelpers.toDTOs),
        .required("ProjectRole", CDProjectRole.self, \.projectRoles, BackupServiceHelpers.toDTOs)
    ]

    private static let workAndLessonCollectors: [EntityCollector] = [
        .optional(
            "WorkModel", CDWorkModel.self, \.workModels, BackupDTOTransformers.toDTOs,
            announcing: .init(0.42, "Collecting work tracking\u{2026}")
        ),
        .optional("WorkCheckIn", CDWorkCheckIn.self, \.workCheckIns, BackupDTOTransformers.toDTOs),
        .optional("WorkStep", CDWorkStep.self, \.workSteps, BackupDTOTransformers.toDTOs),
        .optional(
            "WorkParticipantEntity", CDWorkParticipantEntity.self, \.workParticipants, BackupDTOTransformers.toDTOs
        ),
        .optional("PracticeSession", CDPracticeSession.self, \.practiceSessions, BackupDTOTransformers.toDTOs),
        .optional(
            "LessonAttachment", CDLessonAttachment.self, \.lessonAttachments, BackupDTOTransformers.toDTOs,
            announcing: .init(0.50, "Collecting lesson extras\u{2026}")
        ),
        .optional(
            "LessonPresentation", CDLessonPresentation.self, \.lessonPresentations, BackupDTOTransformers.toDTOs
        ),
        .optional("LessonRecallCheck", CDLessonRecallCheck.self, \.recallChecks, BackupDTOTransformers.toDTOs),
        .optional("SampleWork", CDSampleWork.self, \.sampleWorks, BackupDTOTransformers.toDTOs),
        .optional("SampleWorkStep", CDSampleWorkStep.self, \.sampleWorkSteps, BackupDTOTransformers.toDTOs)
    ]

    private static let templateAndTrackCollectors: [EntityCollector] = [
        .optional(
            "NoteTemplate", CDNoteTemplate.self, \.noteTemplates, BackupDTOTransformers.toDTOs,
            announcing: .init(0.55, "Collecting templates & tracks\u{2026}")
        ),
        .optional("MeetingTemplate", CDMeetingTemplate.self, \.meetingTemplates, BackupDTOTransformers.toDTOs),
        .optional("Reminder", CDReminder.self, \.reminders, BackupDTOTransformers.toDTOs),
        .optional("CalendarEvent", CDCalendarEvent.self, \.calendarEvents, BackupDTOTransformers.toDTOs),
        .optional("Track", CDTrackEntity.self, \.tracks, BackupDTOTransformers.toDTOs),
        .optional("TrackStep", CDTrackStep.self, \.trackSteps, BackupDTOTransformers.toDTOs),
        .optional(
            "StudentTrackEnrollment", CDStudentTrackEnrollmentEntity.self, \.studentTrackEnrollments,
            BackupDTOTransformers.toDTOs
        ),
        .optional("SequenceTrack", CDSequenceTrack.self, \.sequenceTracks, BackupDTOTransformers.toDTOs)
    ]

    private static let organizationCollectors: [EntityCollector] = [
        .optional(
            "Document", CDDocument.self, \.documents, BackupDTOTransformers.toDTOs,
            announcing: .init(0.65, "Collecting supplies, schedules & issues\u{2026}")
        ),
        .optional("Supply", CDSupply.self, \.supplies, BackupDTOTransformers.toDTOs),
        .optional("Procedure", CDProcedure.self, \.procedures, BackupDTOTransformers.toDTOs),
        .optional("Schedule", CDSchedule.self, \.schedules, BackupDTOTransformers.toDTOs),
        .optional("ScheduleSlot", CDScheduleSlot.self, \.scheduleSlots, BackupDTOTransformers.toDTOs),
        .optional("Issue", CDIssue.self, \.issues, BackupDTOTransformers.toDTOs),
        .optional("IssueAction", CDIssueAction.self, \.issueActions, BackupDTOTransformers.toDTOs),
        .optional(
            "DevelopmentSnapshot", CDDevelopmentSnapshotEntity.self, \.developmentSnapshots,
            BackupDTOTransformers.toDTOs,
            announcing: .init(0.75, "Collecting snapshots & todos\u{2026}")
        ),
        .optional("TodoItem", CDTodoItem.self, \.todoItems, BackupDTOTransformers.toDTOs),
        .optional("TodoSubtask", CDTodoSubtask.self, \.todoSubtasks, BackupDTOTransformers.toDTOs),
        .optional("TodoTemplate", CDTodoTemplate.self, \.todoTemplates, BackupDTOTransformers.toDTOs),
        .optional("TodayAgendaOrder", CDTodayAgendaOrder.self, \.todayAgendaOrders, BackupDTOTransformers.toDTOs),
        .optional(
            "PlanningRecommendation", CDPlanningRecommendation.self, \.planningRecommendations,
            BackupDTOTransformers.toDTOs,
            announcing: .init(0.80, "Collecting recommendations & resources\u{2026}")
        ),
        .optional("Resource", CDResource.self, \.resources, BackupDTOTransformers.toDTOs),
        .optional("NoteStudentLink", CDNoteStudentLink.self, \.noteStudentLinks, BackupDTOTransformers.toDTOs),
        .optional(
            "GoingOut", CDGoingOut.self, \.goingOuts, BackupDTOTransformers.toDTOs,
            announcing: .init(0.85, "Collecting going-outs, jobs & transitions\u{2026}")
        ),
        .optional(
            "GoingOutChecklistItem", CDGoingOutChecklistItem.self, \.goingOutChecklistItems,
            BackupDTOTransformers.toDTOs
        ),
        .optional("ClassroomJob", CDClassroomJob.self, \.classroomJobs, BackupDTOTransformers.toDTOs),
        .optional("JobAssignment", CDJobAssignment.self, \.jobAssignments, BackupDTOTransformers.toDTOs),
        .optional(
            "CalendarNote", CDCalendarNote.self, \.calendarNotes, BackupDTOTransformers.toDTOs,
            announcing: .init(0.90, "Collecting calendar notes & meetings\u{2026}")
        ),
        .optional("ScheduledMeeting", CDScheduledMeeting.self, \.scheduledMeetings, BackupDTOTransformers.toDTOs),
        .optional(
            "ClassroomMembership", CDClassroomMembership.self, \.classroomMemberships, BackupDTOTransformers.toDTOs,
            announcing: .init(0.93, "Collecting classroom memberships\u{2026}")
        ),
        .optional(
            "MeetingWorkReview", CDMeetingWorkReview.self, \.meetingWorkReviews, BackupDTOTransformers.toDTOs,
            announcing: .init(0.95, "Collecting meeting work reviews & focus items\u{2026}")
        ),
        .optional("StudentFocusItem", CDStudentFocusItem.self, \.studentFocusItems, BackupDTOTransformers.toDTOs)
    ]

    /// Format v18 (stories, book club, year plan, day pads), v20 (guardians,
    /// parent communications), v21 (teaching-album annotations) and v27 (orders).
    private static let laterFormatCollectors: [EntityCollector] = [
        .optional(
            "DayPad", CDDayPad.self, \.dayPads, BackupDTOTransformers.toDTOs,
            announcing: .init(0.97, "Collecting stories, book club & year plan\u{2026}")
        ),
        .optional("YearPlanEntry", CDYearPlanEntry.self, \.yearPlanEntries, BackupDTOTransformers.toDTOs),
        .optional(
            "LessonSequenceSettings", CDLessonSequenceSettings.self, \.lessonSequenceSettings,
            BackupDTOTransformers.toDTOs
        ),
        .optional("Story", CDStory.self, \.stories, BackupDTOTransformers.toDTOs),
        .optional("BookClubPacket", CDBookClubPacket.self, \.bookClubPackets, BackupDTOTransformers.toDTOs),
        .optional("BookClubSession", CDBookClubSession.self, \.bookClubSessions, BackupDTOTransformers.toDTOs),
        .optional("BookClubMeeting", CDBookClubMeeting.self, \.bookClubMeetings, BackupDTOTransformers.toDTOs),
        .optional(
            "Guardian", CDGuardian.self, \.guardians, BackupDTOTransformers.toDTOs,
            announcing: .init(0.98, "Collecting guardians & parent communications\u{2026}")
        ),
        .optional(
            "ParentCommunication", CDParentCommunication.self, \.parentCommunications, BackupDTOTransformers.toDTOs
        ),
        .optional(
            "AlbumBookmark", CDAlbumBookmark.self, \.albumBookmarks, BackupDTOTransformers.toDTOs,
            announcing: .init(0.99, "Collecting album bookmarks & notes\u{2026}")
        ),
        .optional("AlbumPageNote", CDAlbumPageNote.self, \.albumPageNotes, BackupDTOTransformers.toDTOs),
        .optional("AlbumRecentVisit", CDAlbumRecentVisit.self, \.albumRecentVisits, BackupDTOTransformers.toDTOs),
        .optional(
            "AlbumReadingPosition", CDAlbumReadingPosition.self, \.albumReadingPositions, BackupDTOTransformers.toDTOs
        ),
        .optional("AlbumHighlight", CDAlbumHighlight.self, \.albumHighlights, BackupDTOTransformers.toDTOs),
        .optional("AlbumPageInk", CDAlbumPageInk.self, \.albumPageInk, BackupDTOTransformers.toDTOs),
        .optional("OrderItem", CDOrderItem.self, \.orderItems, BackupDTOTransformers.toDTOs)
    ]
}
