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
        let model = viewContext.persistentStoreCoordinator?.managedObjectModel
        func count<T: NSManagedObject>(_ type: T.Type) -> Int {
            // Skip types whose entity doesn't exist in the Core Data model (e.g. legacy stubs)
            guard model?.entitiesByName.values.contains(where: { $0.managedObjectClassName == NSStringFromClass(T.self) }) == true else {
                return 0
            }
            do {
                return try viewContext.fetch(T.fetchRequest() as! NSFetchRequest<T>).count
            } catch {
                logger.warning("Failed to count \(T.self): \(error)")
                return 0
            }
        }

        assign("Student", payload.students.count, 0, count(CDStudent.self))
        assign("Lesson", payload.lessons.count, 0, count(CDLesson.self))
        assign("LessonAssignment", payload.lessonAssignments.count, 0, count(CDLessonAssignment.self))
        assign("Note", payload.notes.count, 0, count(CDNote.self))
        assign("NonSchoolDay", payload.nonSchoolDays.count, 0, count(CDNonSchoolDay.self))
        assign("SchoolDayOverride", payload.schoolDayOverrides.count, 0, count(CDSchoolDayOverride.self))
        assign("StudentMeeting", payload.studentMeetings.count, 0, count(CDStudentMeeting.self))
        assign("CommunityTopic", payload.communityTopics.count, 0, count(CDCommunityTopicEntity.self))
        assign("ProposedSolution", payload.proposedSolutions.count, 0, count(CDProposedSolutionEntity.self))
        assign("CommunityAttachment", payload.communityAttachments.count, 0, count(CDCommunityAttachmentEntity.self))
        assign("AttendanceRecord", payload.attendance.count, 0, count(CDAttendanceRecord.self))
        assign("WorkModel", payload.workModels?.count ?? 0, 0, count(CDWorkModel.self))
        assign("WorkCompletionRecord", payload.workCompletions.count, 0, count(CDWorkCompletionRecord.self))
        assign("Project", payload.projects.count, 0, count(CDProject.self))
        assign("ProjectAssignmentTemplate", payload.projectAssignmentTemplates.count, 0, 0) // Deprecated
        assign("ProjectSession", payload.projectSessions.count, 0, count(CDProjectSession.self))
        assign("ProjectRole", payload.projectRoles.count, 0, count(CDProjectRole.self))
        assign("ProjectTemplateWeek", payload.projectTemplateWeeks.count, 0, 0) // Deprecated
        assign("ProjectWeekRoleAssignment", payload.projectWeekRoleAssignments.count, 0, 0) // Deprecated
        // Format v12+ entities
        assign("GoingOut", payload.goingOuts?.count ?? 0, 0, count(CDGoingOut.self))
        assign("GoingOutChecklistItem", payload.goingOutChecklistItems?.count ?? 0, 0, count(CDGoingOutChecklistItem.self))
        assign("ClassroomJob", payload.classroomJobs?.count ?? 0, 0, count(CDClassroomJob.self))
        assign("JobAssignment", payload.jobAssignments?.count ?? 0, 0, count(CDJobAssignment.self))
        assign("TransitionPlan", payload.transitionPlans?.count ?? 0, 0, count(CDTransitionPlan.self))
        assign(
            "TransitionChecklistItem",
            payload.transitionChecklistItems?.count ?? 0, 0,
            count(CDTransitionChecklistItem.self)
        )
        assign("CalendarNote", payload.calendarNotes?.count ?? 0, 0, count(CDCalendarNote.self))
        assign("ScheduledMeeting", payload.scheduledMeetings?.count ?? 0, 0, count(CDScheduledMeeting.self))
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
            lessonsInStore = Set(try viewContext.fetch(CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>).compactMap(\.id))
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
                acc.sk += 1
                acc.missingLesson += 1
                return
            }
            let hasLesson = lessonsInStore.contains(lessonUUID) || lessonsInPayload.contains(lessonUUID)
            if !hasLesson {
                acc.sk += 1
                acc.missingLesson += 1
            } else if entityExists(CDLessonAssignment.self, la.id) {
                acc.sk += 1
            } else {
                acc.ins += 1
            }
        }
        assign("LessonAssignment", analysis.ins, analysis.sk, 0)
        if analysis.missingLesson > 0 {
            warnings.append(
                "\(analysis.missingLesson) CDLessonAssignment records "
                + "reference missing Lessons and will be skipped."
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
        assignCounts("ProposedSolution", items: payload.proposedSolutions, type: CDProposedSolutionEntity.self) { $0.id }
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

        let attachmentCounts = countFiltered(payload.communityAttachments, type: CDCommunityAttachmentEntity.self) { $0.id }
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
