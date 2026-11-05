import CoreData
import Foundation
@testable import CosmicDaybook

// The table `BackupSpecOracleTests` is driven by: for each of the 38 types the
// backup wrote and restored by hand until "Simplify round two", Phase 7, how
// the frozen copy of that code (as it stood at a906650c0) exported it and how a
// Merge restored it. Each restore is called as `BackupRestoreRun` called it at
// a906650c0 (`+CoreTypes`, `+PlanningTypes`, `+LaterTypes`). `SequenceTrack`
// left with the track entities at schema 23, as main removed it from the code
// this copies.

/// The frozen code, by shorter names.
private typealias OldExport = LegacyBackupDTOTransformers
private typealias OldImport = LegacyBackupEntityImporter

extension BackupSpecOracleTests {

    /// The frozen restore of one archive line into a store.
    typealias LegacyRestore = @MainActor (NSManagedObjectContext) throws -> Void

    /// One hand-written type, as the old code handled it.
    struct OracleType {
        /// The archive's entity name ("Student", "WorkParticipantEntity", …).
        let entityName: String
        /// The Core Data class.
        let managedType: NSManagedObject.Type
        /// Every record of the type in a store, each row as the old code
        /// wrote it into an archive.
        let legacyExport: @MainActor (NSManagedObjectContext) throws -> [Data]
        /// One archive line as the old code restored it: nil when its row type
        /// refused the line (the old reader skipped the entry), otherwise the
        /// restore of it into a store as a Merge did it (`legacyMerge`).
        let legacyImport: @MainActor (Data) -> LegacyRestore?
    }

    /// The table's types, in archive order. Spelled out, rather than read from
    /// the table, so `@Test(arguments:)` can name them.
    nonisolated static let entityNames: [String] = [
        "Student", "Lesson", "LessonAssignment", "Note", "NonSchoolDay", "SchoolDayOverride",
        "StudentMeeting", "CommunityTopic", "CommunityAttachment", "AttendanceRecord", "WorkCompletionRecord",
        "Project", "ProjectSession", "ProjectRole", "WorkModel", "WorkCheckIn", "WorkParticipantEntity",
        "LessonPresentation", "SampleWork", "CalendarEvent", "Document", "Supply", "Procedure",
        "ScheduleSlot", "Issue", "IssueAction", "DevelopmentSnapshot", "TodoItem", "TodayAgendaOrder",
        "PlanningRecommendation", "Resource", "GoingOutChecklistItem", "ScheduledMeeting", "Story",
        "BookClubPacket", "AlbumHighlight", "AlbumPageInk"
    ]

    /// The table. Split into groups only to keep each literal quick to type-check.
    static let oracleTypes: [OracleType] = peopleAndLessonTypes + recordAndWorkTypes + laterTypes

    // MARK: - Building a row

    /// A type whose restore looks up only its own records.
    private static func oracle<Object: NSManagedObject, Row: Codable & BackupRowDTO>(
        _ entityName: String,
        _ type: Object.Type,
        _ row: Row.Type,
        _ export: @escaping @MainActor ([Object]) -> [Row],
        _ restore: @escaping @MainActor (
            [Row], NSManagedObjectContext, OldImport.ExistingLookup<Object>
        ) throws -> Void
    ) -> OracleType {
        oracle(entityName, type, row, export: export) { rows, context, index in
            try restore(rows, context) { try index.existing(type, id: $0) }
        }
    }

    /// A type whose restore also looks up its parent (`…Check:`).
    private static func oracle<Object: NSManagedObject, Parent: NSManagedObject, Row: Codable & BackupRowDTO>( // swiftlint:disable:this function_parameter_count line_length
        _ entityName: String,
        _ type: Object.Type,
        _ row: Row.Type,
        _ export: @escaping @MainActor ([Object]) -> [Row],
        parent: Parent.Type,
        _ restore: @escaping @MainActor (
            [Row], NSManagedObjectContext, OldImport.ExistingLookup<Object>, OldImport.EntityLookup<Parent>
        ) throws -> Void
    ) -> OracleType {
        oracle(entityName, type, row, export: export) { rows, context, index in
            try restore(rows, context, { try index.existing(type, id: $0) }, { try index.related(parent, id: $0) })
        }
    }

    private static func oracle<Object: NSManagedObject, Row: Codable & BackupRowDTO>(
        _ entityName: String,
        _ type: Object.Type,
        _ row: Row.Type,
        export: @escaping @MainActor ([Object]) -> [Row],
        restore: @escaping @MainActor ([Row], NSManagedObjectContext, BackupEntityIndex) throws -> Void
    ) -> OracleType {
        OracleType(
            entityName: entityName,
            managedType: type,
            legacyExport: { context in
                // As the old collector fetched it (`BackupService+LegacyCollector`).
                let encoder = BackupWriter.ndjsonEncoder()
                return try BackupService().fetchAndTransformInBatches(type, using: context) { export($0) }
                    .map { try encoder.encode($0) }
            },
            legacyImport: { line in
                // As the old reader decoded it (`BackupImporter.reconstructPayload`).
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = BackupDateCoding.decodingStrategy
                guard let decoded = try? decoder.decode(Row.self, from: line) else { return nil }
                return { context in
                    try legacyMerge([decoded], entityName: entityName, type: type, into: context, restore: restore)
                }
            }
        )
    }

    /// One type's rows restored as a Merge did it at a906650c0: the rows less
    /// those whose record here changed since (`BackupRestoreRun.keepingNewer`,
    /// with the old rows' own dates, `LegacyBackupDTOs+Decoding.swift`), the old
    /// importer, the values the format predates put back (none at the current
    /// format), the save, and the repair after it — the steps of
    /// `BackupService.importRows` that can touch the type's own records. The
    /// rest touch other types (a note's student links), or nothing in an
    /// in-memory store of the current format (the private-store assignment, the
    /// settings and attendance locks a v30+ backup carries in no settings,
    /// Restock's levels before v37, practice-session copies).
    private static func legacyMerge<Object: NSManagedObject, Row: BackupRowDTO>(
        _ rows: [Row],
        entityName: String,
        type: Object.Type,
        into context: NSManagedObjectContext,
        restore: @MainActor ([Row], NSManagedObjectContext, BackupEntityIndex) throws -> Void
    ) throws {
        let index = BackupEntityIndex(
            context: context,
            formatVersion: BackupWriter.formatVersion,
            container: BackupRestoreScope.container(for: context)
        )
        let isName = BackupEntityRegistry.mergedOnReplaceEntityNames.contains(entityName)
        var taken: [Row] = []
        for row in rows {
            if let stored = try index.storedStamp(type, id: row.id),
               BackupMergeRule.keepsStored(
                   stored, rowChangedAt: row.rowModifiedAt, rowCompletedAt: row.rowCompletedAt,
                   keepsDatedOverDateless: isName
               ) {
                continue
            }
            taken.append(row)
        }
        try restore(taken, context, index)
        index.predatedValues.putBack()
        try context.save()
        try BackupService().repairDenormalizedFields(viewContext: context)
    }

    // MARK: - The types

    private static let peopleAndLessonTypes: [OracleType] = [
        oracle("Student", CDStudent.self, LegacyStudentDTO.self, OldExport.toDTOs) { rows, context, existing in
            _ = try OldImport.importStudents(rows, into: context, existing: existing)
        },
        oracle("Lesson", CDLesson.self, LegacyLessonDTO.self, OldExport.toDTOs, OldImport.importLessons),
        oracle(
            "LessonAssignment", CDLessonAssignment.self, LegacyLessonAssignmentDTO.self, OldExport.toDTOs,
            parent: CDLesson.self, OldImport.importLessonAssignments
        ),
        oracle("Note", CDNote.self, LegacyNoteDTO.self, export: OldExport.toDTOs) { rows, context, index in
            try OldImport.importNotes(rows, into: context, existing: { try index.existing(CDNote.self, id: $0) })
            // Relinked once every type is in: here, the one type restored.
            try OldImport.relinkNoteRelationships(rows.compactMap(LegacyBackupNoteLinks.init), index: index)
        },
        oracle(
            "NonSchoolDay", CDNonSchoolDay.self, LegacyNonSchoolDayDTO.self, OldExport.toDTOs,
            OldImport.importNonSchoolDays
        ),
        oracle(
            "SchoolDayOverride", CDSchoolDayOverride.self, LegacySchoolDayOverrideDTO.self, OldExport.toDTOs,
            OldImport.importSchoolDayOverrides
        ),
        oracle(
            "StudentMeeting", CDStudentMeeting.self, LegacyStudentMeetingDTO.self, OldExport.toDTOs,
            OldImport.importStudentMeetings
        ),
        oracle(
            "CommunityTopic", CDCommunityTopicEntity.self, LegacyCommunityTopicDTO.self, OldExport.toDTOs,
            OldImport.importCommunityTopics
        ),
        oracle(
            "CommunityAttachment", CDCommunityAttachment.self, LegacyCommunityAttachmentDTO.self, OldExport.toDTOs,
            parent: CDCommunityTopicEntity.self, OldImport.importCommunityAttachments
        ),
        oracle(
            "AttendanceRecord", CDAttendanceRecord.self, LegacyAttendanceRecordDTO.self, OldExport.toDTOs,
            OldImport.importAttendanceRecords
        ),
        oracle(
            "WorkCompletionRecord", CDWorkCompletionRecord.self, LegacyWorkCompletionRecordDTO.self,
            OldExport.toDTOs, OldImport.importWorkCompletionRecords
        ),
        oracle("Project", CDProject.self, LegacyProjectDTO.self, OldExport.toDTOs, OldImport.importProjects),
        oracle(
            "ProjectSession", CDProjectSession.self, LegacyProjectSessionDTO.self, OldExport.toDTOs,
            parent: CDProject.self, OldImport.importProjectSessions
        ),
        oracle(
            "ProjectRole", CDProjectRole.self, LegacyProjectRoleDTO.self, OldExport.toDTOs,
            OldImport.importProjectRoles
        )
    ]

    private static let recordAndWorkTypes: [OracleType] = [
        oracle("WorkModel", CDWorkModel.self, LegacyWorkModelDTO.self, OldExport.toDTOs, OldImport.importWorkModels),
        oracle(
            "WorkCheckIn", CDWorkCheckIn.self, LegacyWorkCheckInDTO.self, OldExport.toDTOs,
            parent: CDWorkModel.self, OldImport.importWorkCheckIns
        ),
        oracle(
            "WorkParticipantEntity", CDWorkParticipantEntity.self, LegacyWorkParticipantEntityDTO.self,
            OldExport.toDTOs, parent: CDWorkModel.self, OldImport.importWorkParticipants
        ),
        oracle(
            "LessonPresentation", CDLessonPresentation.self, LegacyLessonPresentationDTO.self, OldExport.toDTOs,
            OldImport.importLessonPresentations
        ),
        oracle(
            "SampleWork", CDSampleWork.self, LegacySampleWorkDTO.self, OldExport.toDTOs,
            parent: CDLesson.self, OldImport.importSampleWorks
        ),
        // Carried, never restored: the restore read its rows and dropped them.
        oracle(
            "CalendarEvent", CDCalendarEvent.self, LegacyCalendarEventDTO.self, export: OldExport.toDTOs
        ) { _, _, _ in },
        oracle("Document", CDDocument.self, LegacyDocumentDTO.self, OldExport.toDTOs, OldImport.importDocuments),
        oracle("Supply", CDSupply.self, LegacySupplyDTO.self, OldExport.toDTOs, OldImport.importSupplies),
        oracle("Procedure", CDProcedure.self, LegacyProcedureDTO.self, OldExport.toDTOs, OldImport.importProcedures),
        oracle(
            "ScheduleSlot", CDScheduleSlot.self, LegacyScheduleSlotDTO.self, OldExport.toDTOs,
            parent: CDSchedule.self, OldImport.importScheduleSlots
        ),
        oracle("Issue", CDIssue.self, LegacyIssueDTO.self, OldExport.toDTOs, OldImport.importIssues),
        oracle(
            "IssueAction", CDIssueAction.self, LegacyIssueActionDTO.self, OldExport.toDTOs,
            parent: CDIssue.self, OldImport.importIssueActions
        )
    ]

    private static let laterTypes: [OracleType] = [
        oracle(
            "DevelopmentSnapshot", CDDevelopmentSnapshotEntity.self, LegacyDevelopmentSnapshotDTO.self,
            OldExport.toDTOs, OldImport.importDevelopmentSnapshots
        ),
        oracle("TodoItem", CDTodoItem.self, LegacyTodoItemDTO.self, OldExport.toDTOs, OldImport.importTodoItems),
        oracle(
            "TodayAgendaOrder", CDTodayAgendaOrder.self, LegacyTodayAgendaOrderDTO.self, OldExport.toDTOs,
            OldImport.importTodayAgendaOrders
        ),
        oracle(
            "PlanningRecommendation", CDPlanningRecommendation.self, LegacyPlanningRecommendationDTO.self,
            OldExport.toDTOs, OldImport.importPlanningRecommendations
        ),
        oracle("Resource", CDResource.self, LegacyResourceDTO.self, OldExport.toDTOs, OldImport.importResources),
        oracle(
            "GoingOutChecklistItem", CDGoingOutChecklistItem.self, LegacyGoingOutChecklistItemDTO.self,
            OldExport.toDTOs, parent: CDGoingOut.self, OldImport.importGoingOutChecklistItems
        ),
        oracle(
            "ScheduledMeeting", CDScheduledMeeting.self, LegacyScheduledMeetingDTO.self, OldExport.toDTOs,
            OldImport.importScheduledMeetings
        ),
        oracle("Story", CDStory.self, LegacyStoryDTO.self, OldExport.toDTOs, OldImport.importStories),
        oracle(
            "BookClubPacket", CDBookClubPacket.self, LegacyBookClubPacketDTO.self, OldExport.toDTOs,
            OldImport.importBookClubPackets
        ),
        oracle(
            "AlbumHighlight", CDAlbumHighlight.self, LegacyAlbumHighlightDTO.self, OldExport.toDTOs,
            OldImport.importAlbumHighlights
        ),
        oracle(
            "AlbumPageInk", CDAlbumPageInk.self, LegacyAlbumPageInkDTO.self, OldExport.toDTOs,
            OldImport.importAlbumPageInk
        )
    ]
}
