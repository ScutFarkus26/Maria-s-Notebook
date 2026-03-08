import Foundation
import SwiftData

// MARK: - Payload Collection

extension IncrementalBackupService {
    struct PayloadCollectionResult {
        let payload: BackupPayload
        let changedCounts: [String: Int]
        let totalCounts: [String: Int]
    }

    fileprivate struct RemainingEntities {
        var nonSchoolDays: [NonSchoolDay] = []
        var schoolDayOverrides: [SchoolDayOverride] = []
        var studentMeetings: [StudentMeeting] = []
        var communityTopics: [CommunityTopic] = []
        var proposedSolutions: [ProposedSolution] = []
        var communityAttachments: [CommunityAttachment] = []
        var attendance: [AttendanceRecord] = []
        var workCompletions: [WorkCompletionRecord] = []
        var projects: [Project] = []
        var projectTemplates: [ProjectAssignmentTemplate] = []
        var projectSessions: [ProjectSession] = []
        var projectRoles: [ProjectRole] = []
        var projectWeeks: [ProjectTemplateWeek] = []
        var projectWeekAssignments: [ProjectWeekRoleAssignment] = []
    }
}

extension IncrementalBackupService {

    func collectPayload(
        modelContext: ModelContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback
    ) throws -> PayloadCollectionResult {

        var changedCounts: [String: Int] = [:]
        var totalCounts: [String: Int] = [:]

        progress(0.1, "Collecting students...")
        let students = fetchFilteredEntities(
            Student.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.2, "Collecting lessons...")
        let lessons = fetchFilteredEntities(
            Lesson.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.35, "Collecting lesson assignments...")
        let lessonAssignments = fetchFilteredEntities(
            LessonAssignment.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        let notes = collectFilteredNotes(
            using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        let remaining = collectRemainingEntities(
            using: modelContext, sinceDate: sinceDate, progress: progress,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        let payload = buildIncrementalPayload(
            students: students, lessons: lessons,
            lessonAssignments: lessonAssignments, notes: notes,
            remaining: remaining
        )

        return PayloadCollectionResult(payload: payload, changedCounts: changedCounts, totalCounts: totalCounts)
    }

    // MARK: - Payload Collection Helpers

    private func fetchFilteredEntities<T: PersistentModel>(
        _ type: T.Type,
        keyPath: KeyPath<T, Date?>? = nil,
        using modelContext: ModelContext,
        sinceDate: Date?,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) -> [T] {
        let descriptor = FetchDescriptor<T>()
        let all: [T]
        do {
            all = try modelContext.fetch(descriptor)
        } catch {
            print("\u{26a0}\u{fe0f} [Backup:collectChangedEntities] Failed to fetch \(T.self): \(error)")
            all = []
        }
        totalCounts[String(describing: type)] = all.count

        guard let sinceDate = sinceDate, let kp = keyPath else {
            changedCounts[String(describing: type)] = all.count
            return all
        }

        let filtered = all.filter { entity in
            guard let date = entity[keyPath: kp] else { return true }
            return date >= sinceDate
        }
        changedCounts[String(describing: type)] = filtered.count
        return filtered
    }

    private func collectFilteredNotes(
        using modelContext: ModelContext,
        sinceDate: Date?,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) -> [Note] {
        // Notes need special handling since updatedAt is non-optional
        let allNotes: [Note]
        do {
            allNotes = try modelContext.fetch(FetchDescriptor<Note>())
        } catch {
            print("\u{26a0}\u{fe0f} [Backup:collectChangedEntities] Failed to fetch Note: \(error)")
            allNotes = []
        }
        totalCounts["Note"] = allNotes.count
        let notes: [Note]
        if let sinceDate = sinceDate {
            notes = allNotes.filter { $0.updatedAt >= sinceDate }
        } else {
            notes = allNotes
        }
        changedCounts["Note"] = notes.count
        return notes
    }

    private func collectRemainingEntities(
        using modelContext: ModelContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) -> RemainingEntities {
        var result = RemainingEntities()
        collectCalendarAndCommunityModels(
            into: &result, using: modelContext, sinceDate: sinceDate,
            progress: progress, changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        collectRecordAndProjectModels(
            into: &result, using: modelContext, sinceDate: sinceDate,
            progress: progress, changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        return result
    }

    // swiftlint:disable:next function_parameter_count
    private func collectCalendarAndCommunityModels(
        into result: inout RemainingEntities,
        using modelContext: ModelContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) {
        progress(0.5, "Collecting calendar data...")
        result.nonSchoolDays = fetchFilteredEntities(
            NonSchoolDay.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.schoolDayOverrides = fetchFilteredEntities(
            SchoolDayOverride.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.6, "Collecting meetings...")
        result.studentMeetings = fetchFilteredEntities(
            StudentMeeting.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.7, "Collecting community data...")
        result.communityTopics = fetchFilteredEntities(
            CommunityTopic.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.proposedSolutions = fetchFilteredEntities(
            ProposedSolution.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.communityAttachments = fetchFilteredEntities(
            CommunityAttachment.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func collectRecordAndProjectModels(
        into result: inout RemainingEntities,
        using modelContext: ModelContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) {
        progress(0.8, "Collecting attendance...")
        result.attendance = fetchFilteredEntities(
            AttendanceRecord.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.workCompletions = fetchFilteredEntities(
            WorkCompletionRecord.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.9, "Collecting projects...")
        result.projects = fetchFilteredEntities(
            Project.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectTemplates = fetchFilteredEntities(
            ProjectAssignmentTemplate.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectSessions = fetchFilteredEntities(
            ProjectSession.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectRoles = fetchFilteredEntities(
            ProjectRole.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectWeeks = fetchFilteredEntities(
            ProjectTemplateWeek.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectWeekAssignments = fetchFilteredEntities(
            ProjectWeekRoleAssignment.self, using: modelContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
    }

    private func buildIncrementalPayload(
        students: [Student],
        lessons: [Lesson],
        lessonAssignments: [LessonAssignment],
        notes: [Note],
        remaining: RemainingEntities
    ) -> BackupPayload {
        let studentDTOs = BackupServiceHelpers.toDTOs(students)
        let lessonDTOs = BackupServiceHelpers.toDTOs(lessons)
        let noteDTOs = BackupServiceHelpers.toDTOs(notes)
        let nonSchoolDTOs = BackupServiceHelpers.toDTOs(remaining.nonSchoolDays)
        let schoolOverrideDTOs = BackupServiceHelpers.toDTOs(remaining.schoolDayOverrides)
        let studentMeetingDTOs = BackupServiceHelpers.toDTOs(remaining.studentMeetings)
        let topicDTOs = BackupServiceHelpers.toDTOs(remaining.communityTopics)
        let solutionDTOs = BackupServiceHelpers.toDTOs(remaining.proposedSolutions)
        let attachmentDTOs = BackupServiceHelpers.toDTOs(remaining.communityAttachments)
        let attendanceDTOs = BackupServiceHelpers.toDTOs(remaining.attendance)
        let workCompletionDTOs = BackupServiceHelpers.toDTOs(remaining.workCompletions)
        let projectDTOs = BackupServiceHelpers.toDTOs(remaining.projects)
        let projectTemplateDTOs = BackupServiceHelpers.toDTOs(remaining.projectTemplates)
        let projectSessionDTOs = BackupServiceHelpers.toDTOs(remaining.projectSessions)
        let projectRoleDTOs = BackupServiceHelpers.toDTOs(remaining.projectRoles)
        let projectWeekDTOs = BackupServiceHelpers.toDTOs(remaining.projectWeeks)
        let projectWeekAssignDTOs = BackupServiceHelpers.toDTOs(remaining.projectWeekAssignments)
        let lessonAssignmentDTOs = mapLessonAssignmentDTOs(lessonAssignments)
        let preferences = BackupPreferencesService.buildPreferencesDTO()

        return BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            lessonAssignments: lessonAssignmentDTOs,
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: studentMeetingDTOs,
            communityTopics: topicDTOs,
            proposedSolutions: solutionDTOs,
            communityAttachments: attachmentDTOs,
            attendance: attendanceDTOs,
            workCompletions: workCompletionDTOs,
            projects: projectDTOs,
            projectAssignmentTemplates: projectTemplateDTOs,
            projectSessions: projectSessionDTOs,
            projectRoles: projectRoleDTOs,
            projectTemplateWeeks: projectWeekDTOs,
            projectWeekRoleAssignments: projectWeekAssignDTOs,
            preferences: preferences
        )
    }

    private func mapLessonAssignmentDTOs(_ lessonAssignments: [LessonAssignment]) -> [LessonAssignmentDTO] {
        lessonAssignments.map { la in
            LessonAssignmentDTO(
                id: la.id,
                createdAt: la.createdAt,
                modifiedAt: la.modifiedAt,
                stateRaw: la.stateRaw,
                scheduledFor: la.scheduledFor,
                presentedAt: la.presentedAt,
                lessonID: la.lessonID,
                studentIDs: la.studentIDs,
                lessonTitleSnapshot: la.lessonTitleSnapshot,
                lessonSubheadingSnapshot: la.lessonSubheadingSnapshot,
                needsPractice: la.needsPractice,
                needsAnotherPresentation: la.needsAnotherPresentation,
                followUpWork: la.followUpWork,
                notes: la.notes,
                trackID: la.trackID,
                trackStepID: la.trackStepID,
                migratedFromLegacyID: la.migratedFromStudentLessonID,
                migratedFromPresentationID: la.migratedFromPresentationID
            )
        }
    }
}
