// BackupImporter+EntityDecoders.swift
// Which DTO type each archive entity's rows decode to, and where they go.

import Foundation

extension BackupImporter {

    /// How one entity's NDJSON rows are read: each row decoded, in order, with
    /// that entity's DTO type, and then either all kept in the entity's
    /// `BackupPayload` field (`assign`, the restore) or handed over one at a
    /// time and dropped (`visit`, the preview). Both stop at the first row
    /// that does not decode and throw its error, so a restore and a preview
    /// skip exactly the same entries.
    nonisolated struct EntityDecoder: Sendable {
        let assign: @Sendable (inout BackupPayload, [Data], JSONDecoder) throws -> Void
        let visit: @Sendable ([Data], JSONDecoder, (any Sendable) -> Void) throws -> Void
    }

    private nonisolated static func decodeAll<T: Decodable>(
        _ type: T.Type,
        _ lines: [Data],
        _ decoder: JSONDecoder
    ) throws -> [T] {
        try lines.map { try decoder.decode(T.self, from: $0) }
    }

    private nonisolated static func visitAll<T: Decodable & Sendable>(
        _ type: T.Type,
        _ lines: [Data],
        _ decoder: JSONDecoder,
        _ visit: (any Sendable) -> Void
    ) throws {
        for line in lines {
            visit(try decoder.decode(T.self, from: line))
        }
    }

    /// A row for one of the payload's always-present arrays.
    private nonisolated static func rows<T: Decodable & Sendable>(
        _ type: T.Type,
        _ field: WritableKeyPath<BackupPayload, [T]> & Sendable
    ) -> EntityDecoder {
        EntityDecoder(
            assign: { payload, lines, decoder in payload[keyPath: field] = try decodeAll(T.self, lines, decoder) },
            visit: { lines, decoder, visit in try visitAll(T.self, lines, decoder, visit) }
        )
    }

    /// A row for one of the payload's later-format (optional) arrays.
    private nonisolated static func optionalRows<T: Decodable & Sendable>(
        _ type: T.Type,
        _ field: WritableKeyPath<BackupPayload, [T]?> & Sendable
    ) -> EntityDecoder {
        EntityDecoder(
            assign: { payload, lines, decoder in payload[keyPath: field] = try decodeAll(T.self, lines, decoder) },
            visit: { lines, decoder, visit in try visitAll(T.self, lines, decoder, visit) }
        )
    }

    /// Entity name → how its rows decode. Split into groups only to keep each
    /// literal quick to type-check; a name listed twice traps the first time
    /// the table is read, as a duplicate key in one dictionary literal did.
    nonisolated static let entityDecoders: [String: EntityDecoder] = Dictionary(
        uniqueKeysWithValues: coreDecoders + workAndTrackDecoders + organizationDecoders + laterFormatDecoders
    )

    /// Core (required) arrays.
    private nonisolated static let coreDecoders: [(String, EntityDecoder)] = [
        ("Student", rows(StudentDTO.self, \.students)),
        ("Lesson", rows(LessonDTO.self, \.lessons)),
        ("LessonAssignment", rows(LessonAssignmentDTO.self, \.lessonAssignments)),
        ("Note", rows(NoteDTO.self, \.notes)),
        ("NonSchoolDay", rows(NonSchoolDayDTO.self, \.nonSchoolDays)),
        ("SchoolDayOverride", rows(SchoolDayOverrideDTO.self, \.schoolDayOverrides)),
        ("StudentMeeting", rows(StudentMeetingDTO.self, \.studentMeetings)),
        ("CommunityTopic", rows(CommunityTopicDTO.self, \.communityTopics)),
        ("ProposedSolution", rows(ProposedSolutionDTO.self, \.proposedSolutions)),
        ("CommunityAttachment", rows(CommunityAttachmentDTO.self, \.communityAttachments)),
        ("AttendanceRecord", rows(AttendanceRecordDTO.self, \.attendance)),
        ("WorkCompletionRecord", rows(WorkCompletionRecordDTO.self, \.workCompletions)),
        ("Project", rows(ProjectDTO.self, \.projects)),
        ("ProjectSession", rows(ProjectSessionDTO.self, \.projectSessions)),
        ("ProjectRole", rows(ProjectRoleDTO.self, \.projectRoles))
    ]

    /// Optional v8+ extensions: work, lesson extras, templates and tracks.
    private nonisolated static let workAndTrackDecoders: [(String, EntityDecoder)] = [
        ("WorkModel", optionalRows(WorkModelDTO.self, \.workModels)),
        ("WorkCheckIn", optionalRows(WorkCheckInDTO.self, \.workCheckIns)),
        ("WorkStep", optionalRows(WorkStepDTO.self, \.workSteps)),
        ("WorkParticipantEntity", optionalRows(WorkParticipantEntityDTO.self, \.workParticipants)),
        ("PracticeSession", optionalRows(PracticeSessionDTO.self, \.practiceSessions)),
        ("LessonAttachment", optionalRows(LessonAttachmentDTO.self, \.lessonAttachments)),
        ("LessonPresentation", optionalRows(LessonPresentationDTO.self, \.lessonPresentations)),
        ("LessonRecallCheck", optionalRows(LessonRecallCheckDTO.self, \.recallChecks)),
        ("SampleWork", optionalRows(SampleWorkDTO.self, \.sampleWorks)),
        ("SampleWorkStep", optionalRows(SampleWorkStepDTO.self, \.sampleWorkSteps)),
        ("NoteTemplate", optionalRows(NoteTemplateDTO.self, \.noteTemplates)),
        ("MeetingTemplate", optionalRows(MeetingTemplateDTO.self, \.meetingTemplates)),
        ("Reminder", optionalRows(ReminderDTO.self, \.reminders)),
        ("CalendarEvent", optionalRows(CalendarEventDTO.self, \.calendarEvents)),
        ("Track", optionalRows(TrackDTO.self, \.tracks)),
        ("TrackStep", optionalRows(TrackStepDTO.self, \.trackSteps)),
        ("StudentTrackEnrollment", optionalRows(StudentTrackEnrollmentDTO.self, \.studentTrackEnrollments)),
        ("SequenceTrack", optionalRows(SequenceTrackDTO.self, \.sequenceTracks))
    ]

    /// Optional v8+ extensions: documents, supplies, schedules, issues, todos, jobs, meetings.
    private nonisolated static let organizationDecoders: [(String, EntityDecoder)] = [
        ("Document", optionalRows(DocumentDTO.self, \.documents)),
        ("Supply", optionalRows(SupplyDTO.self, \.supplies)),
        ("Procedure", optionalRows(ProcedureDTO.self, \.procedures)),
        ("Schedule", optionalRows(ScheduleDTO.self, \.schedules)),
        ("ScheduleSlot", optionalRows(ScheduleSlotDTO.self, \.scheduleSlots)),
        ("Issue", optionalRows(IssueDTO.self, \.issues)),
        ("IssueAction", optionalRows(IssueActionDTO.self, \.issueActions)),
        ("DevelopmentSnapshot", optionalRows(DevelopmentSnapshotDTO.self, \.developmentSnapshots)),
        ("TodoItem", optionalRows(TodoItemDTO.self, \.todoItems)),
        ("TodoSubtask", optionalRows(TodoSubtaskDTO.self, \.todoSubtasks)),
        ("TodoTemplate", optionalRows(TodoTemplateDTO.self, \.todoTemplates)),
        ("TodayAgendaOrder", optionalRows(TodayAgendaOrderDTO.self, \.todayAgendaOrders)),
        ("PlanningRecommendation", optionalRows(PlanningRecommendationDTO.self, \.planningRecommendations)),
        ("Resource", optionalRows(ResourceDTO.self, \.resources)),
        ("NoteStudentLink", optionalRows(NoteStudentLinkDTO.self, \.noteStudentLinks)),
        ("GoingOut", optionalRows(GoingOutDTO.self, \.goingOuts)),
        ("GoingOutChecklistItem", optionalRows(GoingOutChecklistItemDTO.self, \.goingOutChecklistItems)),
        ("ClassroomJob", optionalRows(ClassroomJobDTO.self, \.classroomJobs)),
        ("JobAssignment", optionalRows(JobAssignmentDTO.self, \.jobAssignments)),
        ("CalendarNote", optionalRows(CalendarNoteDTO.self, \.calendarNotes)),
        ("ScheduledMeeting", optionalRows(ScheduledMeetingDTO.self, \.scheduledMeetings)),
        ("ClassroomMembership", optionalRows(ClassroomMembershipDTO.self, \.classroomMemberships)),
        ("MeetingWorkReview", optionalRows(MeetingWorkReviewDTO.self, \.meetingWorkReviews)),
        ("StudentFocusItem", optionalRows(StudentFocusItemDTO.self, \.studentFocusItems))
    ]

    /// Format v18+, v20+ (families), v21+ (teaching-album annotations) and v27+ (orders).
    private nonisolated static let laterFormatDecoders: [(String, EntityDecoder)] = [
        ("DayPad", optionalRows(DayPadDTO.self, \.dayPads)),
        ("YearPlanEntry", optionalRows(YearPlanEntryDTO.self, \.yearPlanEntries)),
        ("LessonSequenceSettings", optionalRows(LessonSequenceSettingsDTO.self, \.lessonSequenceSettings)),
        ("Story", optionalRows(StoryDTO.self, \.stories)),
        ("BookClubPacket", optionalRows(BookClubPacketDTO.self, \.bookClubPackets)),
        ("BookClubSession", optionalRows(BookClubSessionDTO.self, \.bookClubSessions)),
        ("BookClubMeeting", optionalRows(BookClubMeetingDTO.self, \.bookClubMeetings)),
        ("Guardian", optionalRows(GuardianDTO.self, \.guardians)),
        ("ParentCommunication", optionalRows(ParentCommunicationDTO.self, \.parentCommunications)),
        ("AlbumBookmark", optionalRows(AlbumBookmarkDTO.self, \.albumBookmarks)),
        ("AlbumPageNote", optionalRows(AlbumPageNoteDTO.self, \.albumPageNotes)),
        ("AlbumRecentVisit", optionalRows(AlbumRecentVisitDTO.self, \.albumRecentVisits)),
        ("AlbumReadingPosition", optionalRows(AlbumReadingPositionDTO.self, \.albumReadingPositions)),
        ("AlbumHighlight", optionalRows(AlbumHighlightDTO.self, \.albumHighlights)),
        ("AlbumPageInk", optionalRows(AlbumPageInkDTO.self, \.albumPageInk)),
        ("OrderItem", optionalRows(OrderItemDTO.self, \.orderItems))
    ]
}
