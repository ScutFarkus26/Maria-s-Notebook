import Foundation
import SwiftData
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
    ///   - modelContext: The model context for checking existing entities
    ///   - mode: The restore mode (replace or merge)
    ///   - entityExists: Closure to check if an entity exists by type and ID
    /// - Returns: Analysis result with insert/skip/delete counts per entity type
    static func analyze(
        payload: BackupPayload,
        modelContext: ModelContext,
        mode: BackupService.RestoreMode,
        entityExists: @escaping (any PersistentModel.Type, UUID) -> Bool
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
                modelContext: modelContext,
                assign: assign
            )
        } else {
            analyzeMergeMode(
                payload: payload,
                modelContext: modelContext,
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
        modelContext: ModelContext,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            do {
                return try modelContext.fetch(FetchDescriptor<T>()).count
            } catch {
                logger.warning("Failed to count \(T.self): \(error)")
                return 0
            }
        }

        assign("Student", payload.students.count, 0, count(Student.self))
        assign("Lesson", payload.lessons.count, 0, count(Lesson.self))
        assign("LessonAssignment", payload.lessonAssignments.count, 0, count(LessonAssignment.self))
        assign("Note", payload.notes.count, 0, count(Note.self))
        assign("NonSchoolDay", payload.nonSchoolDays.count, 0, count(NonSchoolDay.self))
        assign("SchoolDayOverride", payload.schoolDayOverrides.count, 0, count(SchoolDayOverride.self))
        assign("StudentMeeting", payload.studentMeetings.count, 0, count(StudentMeeting.self))
        assign("CommunityTopic", payload.communityTopics.count, 0, count(CommunityTopic.self))
        assign("ProposedSolution", payload.proposedSolutions.count, 0, count(ProposedSolution.self))
        assign("CommunityAttachment", payload.communityAttachments.count, 0, count(CommunityAttachment.self))
        assign("AttendanceRecord", payload.attendance.count, 0, count(AttendanceRecord.self))
        assign("WorkModel", payload.workModels?.count ?? 0, 0, count(WorkModel.self))
        assign("WorkCompletionRecord", payload.workCompletions.count, 0, count(WorkCompletionRecord.self))
        assign("Project", payload.projects.count, 0, count(Project.self))
        assign(
            "ProjectAssignmentTemplate",
            payload.projectAssignmentTemplates.count, 0,
            count(ProjectAssignmentTemplate.self)
        )
        assign("ProjectSession", payload.projectSessions.count, 0, count(ProjectSession.self))
        assign("ProjectRole", payload.projectRoles.count, 0, count(ProjectRole.self))
        assign(
            "ProjectTemplateWeek",
            payload.projectTemplateWeeks.count, 0,
            count(ProjectTemplateWeek.self)
        )
        assign(
            "ProjectWeekRoleAssignment",
            payload.projectWeekRoleAssignments.count, 0,
            count(ProjectWeekRoleAssignment.self)
        )
    }

    // MARK: - Merge Mode Analysis

    private static func analyzeMergeMode(
        payload: BackupPayload,
        modelContext: ModelContext,
        entityExists: @escaping (any PersistentModel.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void,
        warnings: inout [String]
    ) {
        // Students
        let studentCounts = BackupCountHelpers.countInsertAndSkip(
            items: payload.students,
            type: Student.self,
            modelContext: modelContext,
            exists: { entityExists(Student.self, $0.id) }
        )
        assign("Student", studentCounts.insert, studentCounts.skip, 0)

        // Lessons
        let lessonCounts = BackupCountHelpers.countInsertAndSkip(
            items: payload.lessons,
            type: Lesson.self,
            modelContext: modelContext,
            exists: { entityExists(Lesson.self, $0.id) }
        )
        assign("Lesson", lessonCounts.insert, lessonCounts.skip, 0)

        // Build lesson lookup sets for presentation/assignment analysis
        let lessonsInStore: Set<UUID>
        do {
            lessonsInStore = Set(try modelContext.fetch(FetchDescriptor<Lesson>()).map(\.id))
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
        entityExists: @escaping (any PersistentModel.Type, UUID) -> Bool,
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
            } else if entityExists(LessonAssignment.self, la.id) {
                acc.sk += 1
            } else {
                acc.ins += 1
            }
        }
        assign("LessonAssignment", analysis.ins, analysis.sk, 0)
        if analysis.missingLesson > 0 {
            warnings.append(
                "\(analysis.missingLesson) LessonAssignment records "
                + "reference missing Lessons and will be skipped."
            )
        }
    }

    private static func analyzeSimpleEntityMerge(
        payload: BackupPayload,
        entityExists: @escaping (any PersistentModel.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func assignCounts<T>(_ key: String, items: [T], type: any PersistentModel.Type, idExtractor: (T) -> UUID) {
            let existing = items.filter { entityExists(type, idExtractor($0)) }
            let new = items.filter { !entityExists(type, idExtractor($0)) }
            assign(key, new.count, existing.count, 0)
        }

        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        assignCounts("Note", items: payload.notes, type: Note.self) { $0.id }
        assignCounts("NonSchoolDay", items: payload.nonSchoolDays, type: NonSchoolDay.self) { $0.id }
        assignCounts("SchoolDayOverride", items: payload.schoolDayOverrides, type: SchoolDayOverride.self) { $0.id }
        assignCounts("StudentMeeting", items: payload.studentMeetings, type: StudentMeeting.self) { $0.id }
        assignCounts("CommunityTopic", items: payload.communityTopics, type: CommunityTopic.self) { $0.id }
        assignCounts("ProposedSolution", items: payload.proposedSolutions, type: ProposedSolution.self) { $0.id }
    }

    private static func analyzeFilteredEntityMerge(
        payload: BackupPayload,
        entityExists: @escaping (any PersistentModel.Type, UUID) -> Bool,
        assign: (_ key: String, _ ins: Int, _ sk: Int, _ del: Int) -> Void
    ) {
        func countFiltered<T>(
            _ items: [T],
            type: any PersistentModel.Type,
            idExtractor: (T) -> UUID
        ) -> (ins: Int, sk: Int) {
            let existing = items.filter { entityExists(type, idExtractor($0)) }
            let new = items.filter { !entityExists(type, idExtractor($0)) }
            return (new.count, existing.count)
        }

        let attachmentCounts = countFiltered(payload.communityAttachments, type: CommunityAttachment.self) { $0.id }
        assign("CommunityAttachment", attachmentCounts.ins, attachmentCounts.sk, 0)

        let attendanceCounts = countFiltered(payload.attendance, type: AttendanceRecord.self) { $0.id }
        assign("AttendanceRecord", attendanceCounts.ins, attendanceCounts.sk, 0)

        let completionCounts = countFiltered(payload.workCompletions, type: WorkCompletionRecord.self) { $0.id }
        assign("WorkCompletionRecord", completionCounts.ins, completionCounts.sk, 0)

        let projectCounts = countFiltered(payload.projects, type: Project.self) { $0.id }
        assign("Project", projectCounts.ins, projectCounts.sk, 0)

        let templateCounts = countFiltered(
            payload.projectAssignmentTemplates,
            type: ProjectAssignmentTemplate.self
        ) { $0.id }
        assign("ProjectAssignmentTemplate", templateCounts.ins, templateCounts.sk, 0)

        let sessionCounts = countFiltered(payload.projectSessions, type: ProjectSession.self) { $0.id }
        assign("ProjectSession", sessionCounts.ins, sessionCounts.sk, 0)

        let roleCounts = countFiltered(payload.projectRoles, type: ProjectRole.self) { $0.id }
        assign("ProjectRole", roleCounts.ins, roleCounts.sk, 0)

        let weekCounts = countFiltered(payload.projectTemplateWeeks, type: ProjectTemplateWeek.self) { $0.id }
        assign("ProjectTemplateWeek", weekCounts.ins, weekCounts.sk, 0)

        let assignmentCounts = countFiltered(
            payload.projectWeekRoleAssignments,
            type: ProjectWeekRoleAssignment.self
        ) { $0.id }
        assign("ProjectWeekRoleAssignment", assignmentCounts.ins, assignmentCounts.sk, 0)
    }
}
