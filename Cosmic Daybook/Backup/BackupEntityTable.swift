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
// `BackupService.importRows` still calls them one by one (through
// `BackupRestoreRun`), asking for each type by its payload field.

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
    /// The `BackupPayload` array holding this type's rows. The restore asks
    /// for a type by this key path (`BackupRestoreRun.rows`), so a type can't
    /// be asked for under the wrong name.
    let field: PartialKeyPath<BackupPayload> & Sendable
    /// The Core Data class, for the registry and replace-mode clearing.
    let managedType: @Sendable () -> NSManagedObject.Type
    let collector: BackupService.EntityCollector
    let serialization: BackupWriter.EntitySerialization
    let decoder: BackupImporter.EntityDecoder
    /// Keeps the first row of each `id` in this type's payload array, as a
    /// new array (the one-pass restore's deduplication, which left the
    /// original rows to its caller, so every type existed twice).
    let deduplicate: @Sendable (inout BackupPayload) -> Void
    /// Moves this type's rows from the first payload into the second, keeping
    /// the first row of each `id` — the same rows, in the same order, as
    /// `deduplicate` — in place: no second copy is made, and the first payload
    /// no longer holds them. How the restore reads a decoded payload one type
    /// at a time (`BackupPayloadSource`).
    let take: @Sendable (_ from: inout BackupPayload, _ into: inout BackupPayload) -> Void

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
            field: field,
            managedType: { Object.self },
            collector: .required(name, type, field, transform, announcing: announcement),
            serialization: BackupWriter.serialization(name) { $0[keyPath: field] },
            decoder: BackupImporter.rows(DTO.self, field),
            deduplicate: { $0[keyPath: field] = uniqueByID($0[keyPath: field]) },
            take: { from, into in
                var rows = from[keyPath: field]
                from[keyPath: field] = []
                removeRepeatedIDs(from: &rows)
                into[keyPath: field] = rows
            }
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
            field: field,
            managedType: { Object.self },
            collector: .optional(name, type, field, transform, announcing: announcement),
            serialization: BackupWriter.serialization(name) { $0[keyPath: field] ?? [] },
            decoder: BackupImporter.optionalRows(DTO.self, field),
            deduplicate: { $0[keyPath: field] = $0[keyPath: field].map(uniqueByID) },
            take: { from, into in
                // An absent type stays absent (nil), as the importers expect.
                guard var rows = from[keyPath: field] else { return }
                from[keyPath: field] = nil
                removeRepeatedIDs(from: &rows)
                into[keyPath: field] = rows
            }
        )
    }

    /// The rows in order, keeping the first of each `id`.
    static func uniqueByID<DTO: BackupRowDTO>(_ rows: [DTO]) -> [DTO] {
        var seen = Set<UUID>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    /// `uniqueByID` in place: every row whose `id` an earlier row has is
    /// removed, and the rest keep their order. Rows with no repeated `id` —
    /// every well-formed backup — are not touched at all.
    static func removeRepeatedIDs<DTO: BackupRowDTO>(from rows: inout [DTO]) {
        var seen = Set<UUID>(minimumCapacity: rows.count)
        let repeated = rows.indices.filter { !seen.insert(rows[$0].id).inserted }
        guard !repeated.isEmpty else { return }
        rows.removeSubranges(RangeSet(repeated, within: rows))
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

    /// The type whose rows `field` holds, or nil for a payload array no
    /// backed-up type fills (the retired project types).
    static func entity(for field: AnyKeyPath) -> BackupEntity? {
        entities.first { ($0.field as AnyKeyPath) == field }
    }

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
            "ProposedSolution", CDProposedSolutionEntity.self, \.proposedSolutions, ProposedSolutionDTO.rows
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
        .optional("WorkStep", CDWorkStep.self, \.workSteps, WorkStepDTO.rows),
        .optional(
            "WorkParticipantEntity", CDWorkParticipantEntity.self, \.workParticipants, BackupDTOTransformers.toDTOs
        ),
        .optional("PracticeSession", CDPracticeSession.self, \.practiceSessions, BackupDTOTransformers.toDTOs),
        .optional(
            "LessonAttachment", CDLessonAttachment.self, \.lessonAttachments, LessonAttachmentDTO.rows,
            announcing: .init(0.50, "Collecting lesson extras\u{2026}")
        ),
        .optional(
            "LessonPresentation", CDLessonPresentation.self, \.lessonPresentations, BackupDTOTransformers.toDTOs
        ),
        .optional("LessonRecallCheck", CDLessonRecallCheck.self, \.recallChecks, LessonRecallCheckDTO.rows),
        .optional("SampleWork", CDSampleWork.self, \.sampleWorks, BackupDTOTransformers.toDTOs),
        .optional("SampleWorkStep", CDSampleWorkStep.self, \.sampleWorkSteps, SampleWorkStepDTO.rows)
    ]

    private static let templateAndTrackEntities: [BackupEntity] = [
        .optional(
            "NoteTemplate", CDNoteTemplate.self, \.noteTemplates, BackupDTOTransformers.toDTOs,
            announcing: .init(0.55, "Collecting templates & tracks\u{2026}")
        ),
        .optional("MeetingTemplate", CDMeetingTemplate.self, \.meetingTemplates, MeetingTemplateDTO.rows),
        .optional("Reminder", CDReminder.self, \.reminders, BackupDTOTransformers.toDTOs),
        .optional("CalendarEvent", CDCalendarEvent.self, \.calendarEvents, BackupDTOTransformers.toDTOs),
        .optional("Track", CDTrackEntity.self, \.tracks, TrackDTO.rows),
        .optional("TrackStep", CDTrackStep.self, \.trackSteps, TrackStepDTO.rows),
        .optional(
            "StudentTrackEnrollment", CDStudentTrackEnrollmentEntity.self, \.studentTrackEnrollments,
            StudentTrackEnrollmentDTO.rows
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
        .optional("Schedule", CDSchedule.self, \.schedules, ScheduleDTO.rows),
        .optional("ScheduleSlot", CDScheduleSlot.self, \.scheduleSlots, BackupDTOTransformers.toDTOs),
        .optional("Issue", CDIssue.self, \.issues, BackupDTOTransformers.toDTOs),
        .optional("IssueAction", CDIssueAction.self, \.issueActions, BackupDTOTransformers.toDTOs),
        .optional(
            "DevelopmentSnapshot", CDDevelopmentSnapshotEntity.self, \.developmentSnapshots,
            BackupDTOTransformers.toDTOs,
            announcing: .init(0.75, "Collecting snapshots & todos\u{2026}")
        ),
        .optional("TodoItem", CDTodoItem.self, \.todoItems, BackupDTOTransformers.toDTOs),
        .optional("TodoSubtask", CDTodoSubtask.self, \.todoSubtasks, TodoSubtaskDTO.rows),
        .optional("TodoTemplate", CDTodoTemplate.self, \.todoTemplates, BackupDTOTransformers.toDTOs),
        .optional("TodayAgendaOrder", CDTodayAgendaOrder.self, \.todayAgendaOrders, BackupDTOTransformers.toDTOs),
        .optional(
            "PlanningRecommendation", CDPlanningRecommendation.self, \.planningRecommendations,
            BackupDTOTransformers.toDTOs,
            announcing: .init(0.80, "Collecting recommendations & resources\u{2026}")
        ),
        .optional("Resource", CDResource.self, \.resources, BackupDTOTransformers.toDTOs),
        .optional("NoteStudentLink", CDNoteStudentLink.self, \.noteStudentLinks, NoteStudentLinkDTO.rows),
        .optional(
            "GoingOut", CDGoingOut.self, \.goingOuts, GoingOutDTO.rows,
            announcing: .init(0.85, "Collecting going-outs, jobs & transitions\u{2026}")
        ),
        .optional(
            "GoingOutChecklistItem", CDGoingOutChecklistItem.self, \.goingOutChecklistItems,
            BackupDTOTransformers.toDTOs
        ),
        .optional("ClassroomJob", CDClassroomJob.self, \.classroomJobs, ClassroomJobDTO.rows),
        .optional("JobAssignment", CDJobAssignment.self, \.jobAssignments, JobAssignmentDTO.rows),
        .optional(
            "CalendarNote", CDCalendarNote.self, \.calendarNotes, CalendarNoteDTO.rows,
            announcing: .init(0.90, "Collecting calendar notes & meetings\u{2026}")
        ),
        .optional("ScheduledMeeting", CDScheduledMeeting.self, \.scheduledMeetings, BackupDTOTransformers.toDTOs),
        .optional(
            "ClassroomMembership", CDClassroomMembership.self, \.classroomMemberships, ClassroomMembershipDTO.rows,
            announcing: .init(0.93, "Collecting classroom memberships\u{2026}")
        ),
        .optional(
            "MeetingWorkReview", CDMeetingWorkReview.self, \.meetingWorkReviews, MeetingWorkReviewDTO.rows,
            announcing: .init(0.95, "Collecting meeting work reviews & focus items\u{2026}")
        ),
        .optional("StudentFocusItem", CDStudentFocusItem.self, \.studentFocusItems, StudentFocusItemDTO.rows)
    ]

    /// Format v18 (stories, book club, year plan, day pads), v20 (guardians,
    /// parent communications), v21 (teaching-album annotations) and v27 (orders).
    private static let laterFormatEntities: [BackupEntity] = [
        .optional(
            "DayPad", CDDayPad.self, \.dayPads, DayPadDTO.rows,
            announcing: .init(0.97, "Collecting stories, book club & year plan\u{2026}")
        ),
        .optional("YearPlanEntry", CDYearPlanEntry.self, \.yearPlanEntries, YearPlanEntryDTO.rows),
        .optional(
            "LessonSequenceSettings", CDLessonSequenceSettings.self, \.lessonSequenceSettings,
            LessonSequenceSettingsDTO.rows
        ),
        .optional("Story", CDStory.self, \.stories, BackupDTOTransformers.toDTOs),
        .optional("BookClubPacket", CDBookClubPacket.self, \.bookClubPackets, BackupDTOTransformers.toDTOs),
        .optional("BookClubSession", CDBookClubSession.self, \.bookClubSessions, BookClubSessionDTO.rows),
        .optional("BookClubMeeting", CDBookClubMeeting.self, \.bookClubMeetings, BookClubMeetingDTO.rows),
        .optional(
            "Guardian", CDGuardian.self, \.guardians, GuardianDTO.rows,
            announcing: .init(0.98, "Collecting guardians & parent communications\u{2026}")
        ),
        .optional(
            "ParentCommunication", CDParentCommunication.self, \.parentCommunications, ParentCommunicationDTO.rows
        ),
        .optional(
            "AlbumBookmark", CDAlbumBookmark.self, \.albumBookmarks, AlbumBookmarkDTO.rows,
            announcing: .init(0.99, "Collecting album bookmarks & notes\u{2026}")
        ),
        .optional("AlbumPageNote", CDAlbumPageNote.self, \.albumPageNotes, AlbumPageNoteDTO.rows),
        .optional("AlbumRecentVisit", CDAlbumRecentVisit.self, \.albumRecentVisits, AlbumRecentVisitDTO.rows),
        .optional(
            "AlbumReadingPosition", CDAlbumReadingPosition.self, \.albumReadingPositions, AlbumReadingPositionDTO.rows
        ),
        .optional("AlbumHighlight", CDAlbumHighlight.self, \.albumHighlights, BackupDTOTransformers.toDTOs),
        .optional("AlbumPageInk", CDAlbumPageInk.self, \.albumPageInk, BackupDTOTransformers.toDTOs),
        .optional("OrderItem", CDOrderItem.self, \.orderItems, OrderItemDTO.rows)
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
extension CommunityAttachmentDTO: BackupRowDTO {}
extension AttendanceRecordDTO: BackupRowDTO {}
extension WorkCompletionRecordDTO: BackupRowDTO {}
extension ProjectDTO: BackupRowDTO {}
extension ProjectSessionDTO: BackupRowDTO {}
extension ProjectRoleDTO: BackupRowDTO {}
extension WorkModelDTO: BackupRowDTO {}
extension WorkCheckInDTO: BackupRowDTO {}
extension WorkParticipantEntityDTO: BackupRowDTO {}
extension PracticeSessionDTO: BackupRowDTO {}
extension LessonPresentationDTO: BackupRowDTO {}
extension SampleWorkDTO: BackupRowDTO {}
extension NoteTemplateDTO: BackupRowDTO {}
extension ReminderDTO: BackupRowDTO {}
extension CalendarEventDTO: BackupRowDTO {}
extension SequenceTrackDTO: BackupRowDTO {}
extension DocumentDTO: BackupRowDTO {}
extension SupplyDTO: BackupRowDTO {}
extension ProcedureDTO: BackupRowDTO {}
extension ScheduleSlotDTO: BackupRowDTO {}
extension IssueDTO: BackupRowDTO {}
extension IssueActionDTO: BackupRowDTO {}
extension DevelopmentSnapshotDTO: BackupRowDTO {}
extension TodoItemDTO: BackupRowDTO {}
extension TodoTemplateDTO: BackupRowDTO {}
extension TodayAgendaOrderDTO: BackupRowDTO {}
extension PlanningRecommendationDTO: BackupRowDTO {}
extension ResourceDTO: BackupRowDTO {}
extension GoingOutChecklistItemDTO: BackupRowDTO {}
extension ScheduledMeetingDTO: BackupRowDTO {}
extension StoryDTO: BackupRowDTO {}
extension BookClubPacketDTO: BackupRowDTO {}
extension AlbumHighlightDTO: BackupRowDTO {}
extension AlbumPageInkDTO: BackupRowDTO {}
