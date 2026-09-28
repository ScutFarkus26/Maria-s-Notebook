import Foundation
import CoreData
import OSLog

/// Analyzes backup payloads to generate preview statistics for restore operations.
///
/// This extracts the analysis logic from BackupService.previewImport() for better
/// testability and separation of concerns. It reads a `BackupPreviewDigest` —
/// row counts and IDs — which is all the analysis ever needed from a backup.
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

    /// Analyzes a whole backup payload; see `analyze(digest:…)`.
    static func analyze(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool
    ) -> AnalysisResult {
        analyze(
            digest: BackupPreviewDigest(payload: payload),
            viewContext: viewContext,
            mode: mode,
            entityExists: entityExists
        )
    }

    /// Analyzes a backup's digest to determine what changes would occur during restore.
    ///
    /// - Parameters:
    ///   - digest: The backup's row counts and IDs
    ///   - viewContext: The model context for checking existing entities
    ///   - mode: The restore mode (replace or merge)
    ///   - entityExists: Closure to check if an entity exists by type and ID
    /// - Returns: Analysis result with insert/skip/delete counts per entity type
    static func analyze(
        digest: BackupPreviewDigest,
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
                digest: digest,
                viewContext: viewContext,
                assign: assign
            )
        } else {
            analyzeMergeMode(
                digest: digest,
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
        digest: BackupPreviewDigest,
        viewContext: NSManagedObjectContext,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        // Replace-mode restore deletes every type in BackupEntityRegistry.allTypes
        // (BackupService+Helpers.deleteAll) and re-inserts the payload, so the
        // preview enumerates that same registry. A hand-picked subset here once
        // under-reported the destructive-restore consent numbers by ~35 types.
        let model = viewContext.persistentStoreCoordinator?.managedObjectModel
        let insertCounts = insertCountsByDisplayName(digest)

        for type in BackupEntityRegistry.allTypes {
            let registryName = BackupEntityRegistry.entityName(for: type)
            guard !BackupEntityRegistry.notYetBackedUpEntityNames.contains(registryName) else { continue }
            let key = displayName(forEntityTypeName: registryName)
            assign(key, insertCounts[key] ?? 0, 0, existingCount(of: type, model: model, in: viewContext))
        }

        // Deprecated payload sections with no live entity behind them: nothing
        // gets deleted, but old backups may still carry records.
        assign("ProjectAssignmentTemplate", digest.projectAssignmentTemplateCount, 0, 0)
        assign("ProjectTemplateWeek", digest.projectTemplateWeekCount, 0, 0)
        assign("ProjectWeekRoleAssignment", digest.projectWeekRoleAssignmentCount, 0, 0)
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

    /// Insert counts from the digest, keyed by the display names derived from
    /// BackupEntityRegistry (see `displayName(forEntityTypeName:)`). The album
    /// annotation types have never been listed here, so replace mode shows no
    /// inserts for them.
    private static func insertCountsByDisplayName(_ digest: BackupPreviewDigest) -> [String: Int] {
        var counts: [String: Int] = [:]
        for key in insertCountKeys {
            counts[key] = digest.count(key == "WorkParticipant" ? "WorkParticipantEntity" : key)
        }
        return counts
    }

    /// Display names reported as replace-mode inserts. Each is also the archive
    /// entity name, except "WorkParticipant" ("WorkParticipantEntity").
    private static let insertCountKeys: [String] = [
        "Student", "Lesson", "LessonAttachment", "LessonAssignment", "LessonPresentation",
        "LessonRecallCheck", "Note", "NoteStudentLink", "NonSchoolDay", "SchoolDayOverride",
        "StudentMeeting", "MeetingTemplate", "CommunityTopic", "ProposedSolution", "CommunityAttachment",
        "AttendanceRecord", "WorkModel", "WorkCompletionRecord", "WorkCheckIn", "WorkParticipant",
        "WorkStep", "SampleWork", "SampleWorkStep", "PracticeSession", "Project",
        "ProjectSession", "ProjectRole", "Issue", "IssueAction", "Track",
        "TrackStep", "StudentTrackEnrollment", "SequenceTrack", "NoteTemplate", "Reminder",
        "CalendarEvent", "Document", "Supply", "Procedure", "Schedule",
        "ScheduleSlot", "DevelopmentSnapshot", "TodoItem", "TodoSubtask", "TodoTemplate",
        "TodayAgendaOrder", "DayPad", "PlanningRecommendation", "Resource", "GoingOut",
        "GoingOutChecklistItem", "ClassroomJob", "JobAssignment", "CalendarNote", "ScheduledMeeting",
        "ClassroomMembership", "MeetingWorkReview", "StudentFocusItem", "YearPlanEntry", "LessonSequenceSettings",
        "Story", "BookClubPacket", "BookClubSession", "BookClubMeeting", "Guardian",
        "ParentCommunication", "OrderItem", "AttendanceDayLock", "SupplyTransaction"
    ]

    // MARK: - Merge Mode Analysis

    private static func analyzeMergeMode(
        digest: BackupPreviewDigest,
        viewContext: NSManagedObjectContext,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void,
        warnings: inout [String]
    ) {
        // Students
        let studentCounts = BackupCountHelpers.countInsertAndSkip(
            items: digest.ids("Student"),
            type: CDStudent.self,
            context: viewContext,
            exists: { entityExists(CDStudent.self, $0) }
        )
        assign("Student", studentCounts.insert, studentCounts.skip, 0)

        // Lessons
        let lessonCounts = BackupCountHelpers.countInsertAndSkip(
            items: digest.ids("Lesson"),
            type: CDLesson.self,
            context: viewContext,
            exists: { entityExists(CDLesson.self, $0) }
        )
        assign("Lesson", lessonCounts.insert, lessonCounts.skip, 0)

        // Build lesson lookup sets for presentation/assignment analysis
        let lessonsInStore: Set<UUID>
        do {
            lessonsInStore = Set(try viewContext.fetch(CDFetchRequest(CDLesson.self)).compactMap(\.id))
        } catch {
            logger.warning("Failed to fetch lessons: \(error)")
            lessonsInStore = Set()
        }
        let lessonsInPayload = Set(digest.ids("Lesson"))

        analyzeLessonAssignmentMerge(
            digest: digest, lessonsInStore: lessonsInStore, lessonsInPayload: lessonsInPayload,
            entityExists: entityExists, assign: assign, warnings: &warnings
        )
        analyzeSimpleEntityMerge(
            digest: digest, entityExists: entityExists, assign: assign
        )
        analyzeFilteredEntityMerge(
            digest: digest, entityExists: entityExists, assign: assign
        )
    }

    // MARK: - Merge Mode Helpers

    private struct ImportAnalysis { var ins = 0; var sk = 0; var missingLesson = 0 }

    // swiftlint:disable:next function_parameter_count
    private static func analyzeLessonAssignmentMerge(
        digest: BackupPreviewDigest,
        lessonsInStore: Set<UUID>,
        lessonsInPayload: Set<UUID>,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void,
        warnings: inout [String]
    ) {
        let analysis = digest.lessonAssignments.reduce(
            into: ImportAnalysis()
        ) { (acc: inout ImportAnalysis, la: BackupPreviewDigest.AssignmentReference) in
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
        digest: BackupPreviewDigest,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func assignCounts(_ key: String, type: NSManagedObject.Type) {
            let ids = digest.ids(key)
            let existing = ids.filter { entityExists(type, $0) }
            let new = ids.filter { !entityExists(type, $0) }
            assign(key, new.count, existing.count, 0)
        }

        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        assignCounts("Note", type: CDNote.self)
        assignCounts("NonSchoolDay", type: CDNonSchoolDay.self)
        assignCounts("SchoolDayOverride", type: CDSchoolDayOverride.self)
        assignCounts("StudentMeeting", type: CDStudentMeeting.self)
        assignCounts("CommunityTopic", type: CDCommunityTopicEntity.self)
        assignCounts("ProposedSolution", type: CDProposedSolutionEntity.self)
    }

    private static func analyzeFilteredEntityMerge(
        digest: BackupPreviewDigest,
        entityExists: @escaping (NSManagedObject.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func countFiltered(_ entityName: String, type: NSManagedObject.Type) -> (ins: Int, sk: Int) {
            let ids = digest.ids(entityName)
            let existing = ids.filter { entityExists(type, $0) }
            let new = ids.filter { !entityExists(type, $0) }
            return (new.count, existing.count)
        }

        let attachmentCounts = countFiltered("CommunityAttachment", type: CDCommunityAttachment.self)
        assign("CommunityAttachment", attachmentCounts.ins, attachmentCounts.sk, 0)

        let attendanceCounts = countFiltered("AttendanceRecord", type: CDAttendanceRecord.self)
        assign("AttendanceRecord", attendanceCounts.ins, attendanceCounts.sk, 0)

        let completionCounts = countFiltered("WorkCompletionRecord", type: CDWorkCompletionRecord.self)
        assign("WorkCompletionRecord", completionCounts.ins, completionCounts.sk, 0)

        let projectCounts = countFiltered("Project", type: CDProject.self)
        assign("Project", projectCounts.ins, projectCounts.sk, 0)

        assign("ProjectAssignmentTemplate", 0, 0, 0)

        let sessionCounts = countFiltered("ProjectSession", type: CDProjectSession.self)
        assign("ProjectSession", sessionCounts.ins, sessionCounts.sk, 0)

        let roleCounts = countFiltered("ProjectRole", type: CDProjectRole.self)
        assign("ProjectRole", roleCounts.ins, roleCounts.sk, 0)

        assign("ProjectTemplateWeek", 0, 0, 0)
        assign("ProjectWeekRoleAssignment", 0, 0, 0)
    }
}
