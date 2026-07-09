import Foundation
import CoreData
import OSLog

/// Analyzes backup payloads to generate preview statistics for restore operations.
///
/// This extracts the analysis logic from BackupService.previewImport() for better
/// testability and separation of concerns.
enum BackupPreviewAnalyzer {
    private static let logger = Logger.backup

    /// Result of analyzing a backup payload against the current database state.
    struct AnalysisResult {
        var inserts: [String: Int] = [:]
        var skips: [String: Int] = [:]
        var deletes: [String: Int] = [:]
        var warnings: [String] = []

        var totalInserts: Int { inserts.values.reduce(0, +) }
        var totalDeletes: Int { deletes.values.reduce(0, +) }
    }

    /// Analyzes a backup payload to determine what changes would occur during restore.
    ///
    /// - Parameters:
    ///   - payload: The backup payload to analyze
    ///   - viewContext: The model context for checking existing entities
    ///   - mode: The restore mode (replace or merge)
    ///   - entityExists: Closure to check if an entity exists by type and ID
    /// - Returns: Analysis result with insert/skip/delete counts per entity type
    static func analyze(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool
    ) -> AnalysisResult {
        // Use separate dictionaries to avoid Swift exclusivity violations
        // (can't have closure capturing result while also passing &result.warnings)
        var inserts: [String: Int] = [:]
        var skips: [String: Int] = [:]
        var deletes: [String: Int] = [:]
        var warnings: [String] = []

        func assign(_ key: String, ins: Int, sk: Int = 0, del: Int = 0) {
            inserts[key] = ins
            skips[key] = sk
            deletes[key] = del
        }

        if mode == .replace {
            analyzeReplaceMode(
                payload: payload,
                viewContext: viewContext,
                assign: assign
            )
        } else {
            analyzeMergeMode(
                payload: payload,
                viewContext: viewContext,
                entityExists: entityExists,
                assign: assign,
                warnings: &warnings
            )
        }

        return AnalysisResult(inserts: inserts, skips: skips, deletes: deletes, warnings: warnings)
    }

    // MARK: - Replace Mode Analysis

    private static func analyzeReplaceMode(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        // Replace-mode restore deletes every type in BackupEntityRegistry.allTypes
        // (BackupService+Helpers.deleteAll) and re-inserts the payload, so the
        // preview enumerates that same registry. A hand-picked subset here once
        // under-reported the destructive-restore consent numbers by ~35 types.
        let model = viewContext.persistentStoreCoordinator?.managedObjectModel
        let insertCounts = payloadInsertCounts(payload)

        for type in BackupEntityRegistry.allTypes {
            let registryName = BackupEntityRegistry.entityName(for: type)
            guard !BackupEntityRegistry.notYetBackedUpEntityNames.contains(registryName) else { continue }
            let key = displayName(forEntityTypeName: registryName)
            assign(key, insertCounts[key] ?? 0, 0, existingCount(of: type, model: model, in: viewContext))
        }

        // Deprecated payload sections with no live entity behind them: nothing
        // gets deleted, but old backups may still carry records.
        assign("ProjectAssignmentTemplate", payload.projectAssignmentTemplates.count, 0, 0)
        assign("ProjectTemplateWeek", payload.projectTemplateWeeks.count, 0, 0)
        assign("ProjectWeekRoleAssignment", payload.projectWeekRoleAssignments.count, 0, 0)
    }

    /// "CDCommunityTopicEntity" → "CommunityTopic"
    private static func displayName(forEntityTypeName name: String) -> String {
        var result = name
        if result.hasPrefix("CD") { result.removeFirst(2) }
        if result.hasSuffix("Entity") { result.removeLast("Entity".count) }
        return result
    }

    private static func existingCount(
        of type: NSManagedObject.Type,
        model: NSManagedObjectModel?,
        in viewContext: NSManagedObjectContext
    ) -> Int {
        // Skip types whose entity doesn't exist in the Core Data model (legacy stubs)
        let className = NSStringFromClass(type)
        guard let entityName = model?.entitiesByName
            .first(where: { $0.value.managedObjectClassName == className })?.key else {
            return 0
        }
        do {
            return try viewContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
        } catch {
            logger.warning("Failed to count \(entityName): \(error)")
            return 0
        }
    }

    /// Insert counts from the payload, keyed by the display names derived from
    /// BackupEntityRegistry (see `displayName(forEntityTypeName:)`).
    // swiftlint:disable:next function_body_length
    private static func payloadInsertCounts(_ payload: BackupPayload) -> [String: Int] {
        [
            "Student": payload.students.count,
            "Lesson": payload.lessons.count,
            "LessonAttachment": payload.lessonAttachments?.count ?? 0,
            "LessonAssignment": payload.lessonAssignments.count,
            "LessonPresentation": payload.lessonPresentations?.count ?? 0,
            "LessonRecallCheck": payload.recallChecks?.count ?? 0,
            "Note": payload.notes.count,
            "NoteStudentLink": payload.noteStudentLinks?.count ?? 0,
            "NonSchoolDay": payload.nonSchoolDays.count,
            "SchoolDayOverride": payload.schoolDayOverrides.count,
            "StudentMeeting": payload.studentMeetings.count,
            "MeetingTemplate": payload.meetingTemplates?.count ?? 0,
            "CommunityTopic": payload.communityTopics.count,
            "ProposedSolution": payload.proposedSolutions.count,
            "CommunityAttachment": payload.communityAttachments.count,
            "AttendanceRecord": payload.attendance.count,
            "WorkModel": payload.workModels?.count ?? 0,
            "WorkCompletionRecord": payload.workCompletions.count,
            "WorkCheckIn": payload.workCheckIns?.count ?? 0,
            "WorkParticipant": payload.workParticipants?.count ?? 0,
            "WorkStep": payload.workSteps?.count ?? 0,
            "SampleWork": payload.sampleWorks?.count ?? 0,
            "SampleWorkStep": payload.sampleWorkSteps?.count ?? 0,
            "PracticeSession": payload.practiceSessions?.count ?? 0,
            "Project": payload.projects.count,
            "ProjectSession": payload.projectSessions.count,
            "ProjectRole": payload.projectRoles.count,
            "Issue": payload.issues?.count ?? 0,
            "IssueAction": payload.issueActions?.count ?? 0,
            "Track": payload.tracks?.count ?? 0,
            "TrackStep": payload.trackSteps?.count ?? 0,
            "StudentTrackEnrollment": payload.studentTrackEnrollments?.count ?? 0,
            "SequenceTrack": payload.sequenceTracks?.count ?? 0,
            "NoteTemplate": payload.noteTemplates?.count ?? 0,
            "Reminder": payload.reminders?.count ?? 0,
            "CalendarEvent": payload.calendarEvents?.count ?? 0,
            "Document": payload.documents?.count ?? 0,
            "Supply": payload.supplies?.count ?? 0,
            "Procedure": payload.procedures?.count ?? 0,
            "Schedule": payload.schedules?.count ?? 0,
            "ScheduleSlot": payload.scheduleSlots?.count ?? 0,
            "DevelopmentSnapshot": payload.developmentSnapshots?.count ?? 0,
            "TodoItem": payload.todoItems?.count ?? 0,
            "TodoSubtask": payload.todoSubtasks?.count ?? 0,
            "TodoTemplate": payload.todoTemplates?.count ?? 0,
            "TodayAgendaOrder": payload.todayAgendaOrders?.count ?? 0,
            "DayPad": payload.dayPads?.count ?? 0,
            "PlanningRecommendation": payload.planningRecommendations?.count ?? 0,
            "Resource": payload.resources?.count ?? 0,
            "GoingOut": payload.goingOuts?.count ?? 0,
            "GoingOutChecklistItem": payload.goingOutChecklistItems?.count ?? 0,
            "ClassroomJob": payload.classroomJobs?.count ?? 0,
            "JobAssignment": payload.jobAssignments?.count ?? 0,
            "CalendarNote": payload.calendarNotes?.count ?? 0,
            "ScheduledMeeting": payload.scheduledMeetings?.count ?? 0,
            "ClassroomMembership": payload.classroomMemberships?.count ?? 0,
            "MeetingWorkReview": payload.meetingWorkReviews?.count ?? 0,
            "StudentFocusItem": payload.studentFocusItems?.count ?? 0,
            "YearPlanEntry": payload.yearPlanEntries?.count ?? 0,
            "LessonSequenceSettings": payload.lessonSequenceSettings?.count ?? 0,
            "Story": payload.stories?.count ?? 0,
            "BookClubPacket": payload.bookClubPackets?.count ?? 0,
            "BookClubSession": payload.bookClubSessions?.count ?? 0,
            "BookClubMeeting": payload.bookClubMeetings?.count ?? 0
        ]
    }

    // MARK: - Merge Mode Analysis

    private static func analyzeMergeMode(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void,
        warnings: inout [String]
    ) {
        // Students
        let studentCounts = BackupCountHelpers.countInsertAndSkip(
            items: payload.students,
            type: CDStudent.self,
            context: viewContext,
            exists: { entityExists(CDStudent.self, $0.id) }
        )
        assign("Student", studentCounts.insert, studentCounts.skip, 0)

        // Lessons
        let lessonCounts = BackupCountHelpers.countInsertAndSkip(
            items: payload.lessons,
            type: CDLesson.self,
            context: viewContext,
            exists: { entityExists(CDLesson.self, $0.id) }
        )
        assign("Lesson", lessonCounts.insert, lessonCounts.skip, 0)

        // Build lesson lookup sets for presentation/assignment analysis
        let lessonsInStore: Set<UUID>
        do {
            lessonsInStore = Set(try viewContext.fetch(NSFetchRequest<CDLesson>(entityName: "Lesson")).compactMap(\.id))
        } catch {
            logger.warning("Failed to fetch lessons: \(error)")
            lessonsInStore = Set()
        }
        let lessonsInPayload = Set(payload.lessons.map(\.id))

        analyzeLessonAssignmentMerge(
            payload: payload, lessonsInStore: lessonsInStore, lessonsInPayload: lessonsInPayload,
            entityExists: entityExists, assign: assign, warnings: &warnings
        )
        analyzeSimpleEntityMerge(
            payload: payload, entityExists: entityExists, assign: assign
        )
        analyzeFilteredEntityMerge(
            payload: payload, entityExists: entityExists, assign: assign
        )
    }

    // MARK: - Merge Mode Helpers

    private struct ImportAnalysis { var ins = 0; var sk = 0; var missingLesson = 0 }

    // swiftlint:disable:next function_parameter_count
    private static func analyzeLessonAssignmentMerge(
        payload: BackupPayload,
        lessonsInStore: Set<UUID>,
        lessonsInPayload: Set<UUID>,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void,
        warnings: inout [String]
    ) {
        let analysis = payload.lessonAssignments.reduce(
            into: ImportAnalysis()
        ) { (acc: inout ImportAnalysis, la: LessonAssignmentDTO) in
            guard let lessonUUID = UUID(uuidString: la.lessonID) else {
                // The importer skips assignments whose lessonID isn't a valid UUID.
                acc.sk += 1
                return
            }
            if entityExists(CDLessonAssignment.self, la.id) {
                acc.sk += 1
                return
            }
            // The importer inserts assignments even when the lesson is missing
            // from both the payload and the library — they restore unlinked,
            // they are NOT skipped (BackupEntityImporter+Lessons).
            acc.ins += 1
            if !lessonsInStore.contains(lessonUUID) && !lessonsInPayload.contains(lessonUUID) {
                acc.missingLesson += 1
            }
        }
        assign("LessonAssignment", analysis.ins, analysis.sk, 0)
        if analysis.missingLesson > 0 {
            warnings.append(
                "\(analysis.missingLesson) lesson assignments reference lessons missing "
                + "from both this backup and the library; they will be restored but "
                + "stay unlinked until their lesson exists."
            )
        }
    }

    private static func analyzeSimpleEntityMerge(
        payload: BackupPayload,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func assignCounts<T>(_ key: String, items: [T], type: NSManagedObject.Type, idExtractor: (T) -> UUID) {
            let existing = items.filter { entityExists(type, idExtractor($0)) }
            let new = items.filter { !entityExists(type, idExtractor($0)) }
            assign(key, new.count, existing.count, 0)
        }

        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        assignCounts("Note", items: payload.notes, type: CDNote.self) { $0.id }
        assignCounts("NonSchoolDay", items: payload.nonSchoolDays, type: CDNonSchoolDay.self) { $0.id }
        assignCounts("SchoolDayOverride", items: payload.schoolDayOverrides, type: CDSchoolDayOverride.self) { $0.id }
        assignCounts("StudentMeeting", items: payload.studentMeetings, type: CDStudentMeeting.self) { $0.id }
        assignCounts("CommunityTopic", items: payload.communityTopics, type: CDCommunityTopicEntity.self) { $0.id }
        assignCounts(
            "ProposedSolution",
            items: payload.proposedSolutions,
            type: CDProposedSolutionEntity.self
        ) { $0.id }
    }

    private static func analyzeFilteredEntityMerge(
        payload: BackupPayload,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func countFiltered<T>(
            _ items: [T],
            type: NSManagedObject.Type,
            idExtractor: (T) -> UUID
        ) -> (ins: Int, sk: Int) {
            let existing = items.filter { entityExists(type, idExtractor($0)) }
            let new = items.filter { !entityExists(type, idExtractor($0)) }
            return (new.count, existing.count)
        }

        let attachmentCounts = countFiltered(
            payload.communityAttachments,
            type: CDCommunityAttachmentEntity.self
        ) { $0.id }
        assign("CommunityAttachment", attachmentCounts.ins, attachmentCounts.sk, 0)

        let attendanceCounts = countFiltered(payload.attendance, type: CDAttendanceRecord.self) { $0.id }
        assign("AttendanceRecord", attendanceCounts.ins, attendanceCounts.sk, 0)

        let completionCounts = countFiltered(payload.workCompletions, type: CDWorkCompletionRecord.self) { $0.id }
        assign("WorkCompletionRecord", completionCounts.ins, completionCounts.sk, 0)

        let projectCounts = countFiltered(payload.projects, type: CDProject.self) { $0.id }
        assign("Project", projectCounts.ins, projectCounts.sk, 0)

        assign("ProjectAssignmentTemplate", 0, 0, 0)

        let sessionCounts = countFiltered(payload.projectSessions, type: CDProjectSession.self) { $0.id }
        assign("ProjectSession", sessionCounts.ins, sessionCounts.sk, 0)

        let roleCounts = countFiltered(payload.projectRoles, type: CDProjectRole.self) { $0.id }
        assign("ProjectRole", roleCounts.ins, roleCounts.sk, 0)

        assign("ProjectTemplateWeek", 0, 0, 0)
        assign("ProjectWeekRoleAssignment", 0, 0, 0)
    }
}
