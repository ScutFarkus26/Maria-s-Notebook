import Foundation
import CoreData
import OSLog

// MARK: - Payload Collection

extension IncrementalBackupService {
    struct PayloadCollectionResult {
        let payload: BackupPayload
        let changedCounts: [String: Int]
        let totalCounts: [String: Int]
    }

    fileprivate struct RemainingEntities {
        var nonSchoolDays: [CDNonSchoolDay] = []
        var schoolDayOverrides: [CDSchoolDayOverride] = []
        var studentMeetings: [CDStudentMeeting] = []
        var communityTopics: [CDCommunityTopicEntity] = []
        var proposedSolutions: [CDProposedSolutionEntity] = []
        var communityAttachments: [CDCommunityAttachmentEntity] = []
        var attendance: [CDAttendanceRecord] = []
        var workCompletions: [CDWorkCompletionRecord] = []
        var projects: [CDProject] = []
        var projectTemplates: [CDProjectAssignmentTemplate] = []
        var projectSessions: [CDProjectSession] = []
        var projectRoles: [CDProjectRole] = []
        var projectWeeks: [CDProjectTemplateWeek] = []
        var projectWeekAssignments: [CDProjectWeekRoleAssignment] = []
    }
}

extension IncrementalBackupService {
    private static let logger = Logger.backup

    func collectPayload(
        viewContext: NSManagedObjectContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback
    ) throws -> PayloadCollectionResult {

        var changedCounts: [String: Int] = [:]
        var totalCounts: [String: Int] = [:]

        progress(0.1, "Collecting students...")
        let students = fetchFilteredEntities(
            CDStudent.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.2, "Collecting lessons...")
        let lessons = fetchFilteredEntities(
            CDLesson.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.35, "Collecting lesson assignments...")
        let lessonAssignments = fetchFilteredEntities(
            CDLessonAssignment.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        let notes = collectFilteredNotes(
            using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        let remaining = collectRemainingEntities(
            using: viewContext, sinceDate: sinceDate, progress: progress,
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

    private func fetchFilteredEntities<T: NSManagedObject>(
        _ type: T.Type,
        keyPath: KeyPath<T, Date?>? = nil,
        using viewContext: NSManagedObjectContext,
        sinceDate: Date?,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) -> [T] {
        let descriptor = T.fetchRequest() as! NSFetchRequest<T>
        let all: [T]
        do {
            all = try viewContext.fetch(descriptor)
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to fetch \(T.self, privacy: .public): \(desc, privacy: .public)")
            all = []
        }
        totalCounts[String(describing: type)] = all.count

        guard let sinceDate, let kp = keyPath else {
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
        using viewContext: NSManagedObjectContext,
        sinceDate: Date?,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) -> [CDNote] {
        // Notes need special handling since updatedAt is non-optional
        let allNotes: [CDNote]
        do {
            allNotes = try viewContext.fetch(CDNote.fetchRequest() as! NSFetchRequest<CDNote>)
        } catch {
            Self.logger.warning("Failed to fetch CDNote: \(error.localizedDescription, privacy: .public)")
            allNotes = []
        }
        totalCounts["Note"] = allNotes.count
        let notes: [CDNote]
        if let sinceDate {
            notes = allNotes.filter { ($0.updatedAt ?? .distantPast) >= sinceDate }
        } else {
            notes = allNotes
        }
        changedCounts["Note"] = notes.count
        return notes
    }

    private func collectRemainingEntities(
        using viewContext: NSManagedObjectContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) -> RemainingEntities {
        var result = RemainingEntities()
        collectCalendarAndCommunityModels(
            into: &result, using: viewContext, sinceDate: sinceDate,
            progress: progress, changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        collectRecordAndProjectModels(
            into: &result, using: viewContext, sinceDate: sinceDate,
            progress: progress, changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        return result
    }

    // swiftlint:disable:next function_parameter_count
    private func collectCalendarAndCommunityModels(
        into result: inout RemainingEntities,
        using viewContext: NSManagedObjectContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) {
        progress(0.5, "Collecting calendar data...")
        result.nonSchoolDays = fetchFilteredEntities(
            CDNonSchoolDay.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.schoolDayOverrides = fetchFilteredEntities(
            CDSchoolDayOverride.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.6, "Collecting meetings...")
        result.studentMeetings = fetchFilteredEntities(
            CDStudentMeeting.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.7, "Collecting community data...")
        result.communityTopics = fetchFilteredEntities(
            CDCommunityTopicEntity.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.proposedSolutions = fetchFilteredEntities(
            CDProposedSolutionEntity.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.communityAttachments = fetchFilteredEntities(
            CDCommunityAttachmentEntity.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func collectRecordAndProjectModels(
        into result: inout RemainingEntities,
        using viewContext: NSManagedObjectContext,
        sinceDate: Date?,
        progress: @escaping BackupService.ProgressCallback,
        changedCounts: inout [String: Int],
        totalCounts: inout [String: Int]
    ) {
        progress(0.8, "Collecting attendance...")
        result.attendance = fetchFilteredEntities(
            CDAttendanceRecord.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.workCompletions = fetchFilteredEntities(
            CDWorkCompletionRecord.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )

        progress(0.9, "Collecting projects...")
        result.projects = fetchFilteredEntities(
            CDProject.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectTemplates = fetchFilteredEntities(
            CDProjectAssignmentTemplate.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectSessions = fetchFilteredEntities(
            CDProjectSession.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectRoles = fetchFilteredEntities(
            CDProjectRole.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectWeeks = fetchFilteredEntities(
            CDProjectTemplateWeek.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
        result.projectWeekAssignments = fetchFilteredEntities(
            CDProjectWeekRoleAssignment.self, using: viewContext, sinceDate: sinceDate,
            changedCounts: &changedCounts, totalCounts: &totalCounts
        )
    }

    private func buildIncrementalPayload(
        students: [CDStudent],
        lessons: [CDLesson],
        lessonAssignments: [CDLessonAssignment],
        notes: [CDNote],
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

    private func mapLessonAssignmentDTOs(_ lessonAssignments: [CDLessonAssignment]) -> [LessonAssignmentDTO] {
        lessonAssignments.compactMap { la in
            guard let laID = la.id, let laCreatedAt = la.createdAt, let laModifiedAt = la.modifiedAt else { return nil }
            return LessonAssignmentDTO(
                id: laID,
                createdAt: laCreatedAt,
                modifiedAt: laModifiedAt,
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
