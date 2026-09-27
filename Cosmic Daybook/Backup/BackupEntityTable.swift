// BackupEntityTable.swift
// The one list of backed-up entity types.
//
// Everything that has to name every backed-up type reads this table: the
// collection step (`BackupService.entityCollectors`), the writer's serializers
// (`BackupWriter.entitySerializations`), the importer's decoders
// (`BackupImporter.entityDecoders`), the payload deduplicator and the entity
// registry that replace-mode restore clears. A type added here is collected,
// written, decoded, deduplicated and cleared together; before this table each
// of those kept its own list, and one that missed a type silently dropped its
// records on restore (ClassroomMembership in the deduplicator).
//
// Rows are in archive order, which `BackupStreamingExportTests` pins. The
// restore order is separate: each importer is different, so
// `BackupService.importPayload` still calls them one by one.

import CoreData
import Foundation

/// A backup row type. Every DTO carries its record's `id`, which the payload
/// deduplicator keys on.
nonisolated protocol BackupRowDTO: Codable, Sendable {
    var id: UUID { get }
}

/// One backed-up entity type and everything derived from it.
nonisolated struct BackupEntity: Sendable {
    /// The archive entity name ("Student", "WorkParticipantEntity", …).
    let name: String
    /// The Core Data class, for the registry and replace-mode clearing.
    let managedType: @Sendable () -> NSManagedObject.Type
    let collector: BackupService.EntityCollector
    let serialization: BackupWriter.EntitySerialization
    let decoder: BackupImporter.EntityDecoder
    /// Keeps the first row of each `id` in this type's payload array.
    let deduplicate: @Sendable (inout BackupPayload) -> Void

    /// A type stored in one of the payload's always-present arrays.
    static func required<Object: NSManagedObject, DTO: BackupRowDTO>(
        _ name: String,
        _ type: Object.Type,
        _ field: WritableKeyPath<BackupPayload, [DTO]> & Sendable,
        _ transform: @escaping @MainActor ([Object]) -> [DTO],
        announcing announcement: BackupService.CollectionAnnouncement? = nil
    ) -> BackupEntity {
        BackupEntity(
            name: name,
            managedType: { Object.self },
            collector: .required(name, type, field, transform, announcing: announcement),
            serialization: BackupWriter.serialization(name) { $0[keyPath: field] },
            decoder: BackupImporter.rows(DTO.self, field),
            deduplicate: { $0[keyPath: field] = uniqueByID($0[keyPath: field]) }
        )
    }

    /// A type stored in one of the payload's later-format (optional) arrays.
    static func optional<Object: NSManagedObject, DTO: BackupRowDTO>(
        _ name: String,
        _ type: Object.Type,
        _ field: WritableKeyPath<BackupPayload, [DTO]?> & Sendable,
        _ transform: @escaping @MainActor ([Object]) -> [DTO],
        announcing announcement: BackupService.CollectionAnnouncement? = nil
    ) -> BackupEntity {
        BackupEntity(
            name: name,
            managedType: { Object.self },
            collector: .optional(name, type, field, transform, announcing: announcement),
            serialization: BackupWriter.serialization(name) { $0[keyPath: field] ?? [] },
            decoder: BackupImporter.optionalRows(DTO.self, field),
            deduplicate: { $0[keyPath: field] = $0[keyPath: field].map(uniqueByID) }
        )
    }

    /// The rows in order, keeping the first of each `id`.
    static func uniqueByID<DTO: BackupRowDTO>(_ rows: [DTO]) -> [DTO] {
        var seen = Set<UUID>()
        return rows.filter { seen.insert($0.id).inserted }
    }
}

nonisolated enum BackupEntityTable {
    /// Every backed-up entity type, in archive order. Split into groups only to
    /// keep each array literal quick to type-check.
    static let entities: [BackupEntity] =
        coreEntities + workAndLessonEntities + templateAndTrackEntities
            + organizationEntities + laterFormatEntities

    /// Every entity name, in archive order.
    static var names: [String] { entities.map(\.name) }

    // MARK: - Groups

    private static let coreEntities: [BackupEntity] = [
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

    private static let workAndLessonEntities: [BackupEntity] = [
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

    private static let templateAndTrackEntities: [BackupEntity] = [
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

    private static let organizationEntities: [BackupEntity] = [
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
    private static let laterFormatEntities: [BackupEntity] = [
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

// MARK: - Row types

// Each DTO already has `id: UUID`; conforming here is what lets its table row compile.
extension StudentDTO: BackupRowDTO {}
extension LessonDTO: BackupRowDTO {}
extension LessonAssignmentDTO: BackupRowDTO {}
extension NoteDTO: BackupRowDTO {}
extension NonSchoolDayDTO: BackupRowDTO {}
extension SchoolDayOverrideDTO: BackupRowDTO {}
extension StudentMeetingDTO: BackupRowDTO {}
extension CommunityTopicDTO: BackupRowDTO {}
extension ProposedSolutionDTO: BackupRowDTO {}
extension CommunityAttachmentDTO: BackupRowDTO {}
extension AttendanceRecordDTO: BackupRowDTO {}
extension WorkCompletionRecordDTO: BackupRowDTO {}
extension ProjectDTO: BackupRowDTO {}
extension ProjectSessionDTO: BackupRowDTO {}
extension ProjectRoleDTO: BackupRowDTO {}
extension WorkModelDTO: BackupRowDTO {}
extension WorkCheckInDTO: BackupRowDTO {}
extension WorkStepDTO: BackupRowDTO {}
extension WorkParticipantEntityDTO: BackupRowDTO {}
extension PracticeSessionDTO: BackupRowDTO {}
extension LessonAttachmentDTO: BackupRowDTO {}
extension LessonPresentationDTO: BackupRowDTO {}
extension LessonRecallCheckDTO: BackupRowDTO {}
extension SampleWorkDTO: BackupRowDTO {}
extension SampleWorkStepDTO: BackupRowDTO {}
extension NoteTemplateDTO: BackupRowDTO {}
extension MeetingTemplateDTO: BackupRowDTO {}
extension ReminderDTO: BackupRowDTO {}
extension CalendarEventDTO: BackupRowDTO {}
extension TrackDTO: BackupRowDTO {}
extension TrackStepDTO: BackupRowDTO {}
extension StudentTrackEnrollmentDTO: BackupRowDTO {}
extension SequenceTrackDTO: BackupRowDTO {}
extension DocumentDTO: BackupRowDTO {}
extension SupplyDTO: BackupRowDTO {}
extension ProcedureDTO: BackupRowDTO {}
extension ScheduleDTO: BackupRowDTO {}
extension ScheduleSlotDTO: BackupRowDTO {}
extension IssueDTO: BackupRowDTO {}
extension IssueActionDTO: BackupRowDTO {}
extension DevelopmentSnapshotDTO: BackupRowDTO {}
extension TodoItemDTO: BackupRowDTO {}
extension TodoSubtaskDTO: BackupRowDTO {}
extension TodoTemplateDTO: BackupRowDTO {}
extension TodayAgendaOrderDTO: BackupRowDTO {}
extension PlanningRecommendationDTO: BackupRowDTO {}
extension ResourceDTO: BackupRowDTO {}
extension NoteStudentLinkDTO: BackupRowDTO {}
extension GoingOutDTO: BackupRowDTO {}
extension GoingOutChecklistItemDTO: BackupRowDTO {}
extension ClassroomJobDTO: BackupRowDTO {}
extension JobAssignmentDTO: BackupRowDTO {}
extension CalendarNoteDTO: BackupRowDTO {}
extension ScheduledMeetingDTO: BackupRowDTO {}
extension ClassroomMembershipDTO: BackupRowDTO {}
extension MeetingWorkReviewDTO: BackupRowDTO {}
extension StudentFocusItemDTO: BackupRowDTO {}
extension DayPadDTO: BackupRowDTO {}
extension YearPlanEntryDTO: BackupRowDTO {}
extension LessonSequenceSettingsDTO: BackupRowDTO {}
extension StoryDTO: BackupRowDTO {}
extension BookClubPacketDTO: BackupRowDTO {}
extension BookClubSessionDTO: BackupRowDTO {}
extension BookClubMeetingDTO: BackupRowDTO {}
extension GuardianDTO: BackupRowDTO {}
extension ParentCommunicationDTO: BackupRowDTO {}
extension AlbumBookmarkDTO: BackupRowDTO {}
extension AlbumPageNoteDTO: BackupRowDTO {}
extension AlbumRecentVisitDTO: BackupRowDTO {}
extension AlbumReadingPositionDTO: BackupRowDTO {}
extension AlbumHighlightDTO: BackupRowDTO {}
extension AlbumPageInkDTO: BackupRowDTO {}
extension OrderItemDTO: BackupRowDTO {}
