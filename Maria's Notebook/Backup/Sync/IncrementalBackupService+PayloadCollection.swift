import Foundation
import SwiftData

// MARK: - Payload Collection

    struct PayloadCollectionResult {
        let payload: BackupPayload
        let changedCounts: [String: Int]
        let totalCounts: [String: Int]
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

        // Helper to fetch and filter entities
        func fetchFiltered<T: PersistentModel>(
            _ type: T.Type,
            keyPath: KeyPath<T, Date?>? = nil
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

        progress(0.1, "Collecting students...")
        let students: [Student] = fetchFiltered(Student.self)

        progress(0.2, "Collecting lessons...")
        let lessons: [Lesson] = fetchFiltered(Lesson.self)

        // LegacyPresentation removed -- no longer exported in incremental backups

        progress(0.35, "Collecting lesson assignments...")
        let lessonAssignments: [LessonAssignment] = fetchFiltered(LessonAssignment.self)

        // Phase 6: WorkPlanItem removed from schema - migrated to WorkCheckIn
        // Skip collecting these records (can't reference WorkPlanItem type anymore)

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

        progress(0.5, "Collecting calendar data...")
        let nonSchoolDays: [NonSchoolDay] = fetchFiltered(NonSchoolDay.self)
        let schoolDayOverrides: [SchoolDayOverride] = fetchFiltered(SchoolDayOverride.self)

        progress(0.6, "Collecting meetings...")
        let studentMeetings: [StudentMeeting] = fetchFiltered(StudentMeeting.self)

        progress(0.7, "Collecting community data...")
        let communityTopics: [CommunityTopic] = fetchFiltered(CommunityTopic.self)
        let proposedSolutions: [ProposedSolution] = fetchFiltered(ProposedSolution.self)
        let communityAttachments: [CommunityAttachment] = fetchFiltered(CommunityAttachment.self)

        progress(0.8, "Collecting attendance...")
        let attendance: [AttendanceRecord] = fetchFiltered(AttendanceRecord.self)
        let workCompletions: [WorkCompletionRecord] = fetchFiltered(WorkCompletionRecord.self)

        progress(0.9, "Collecting projects...")
        let projects: [Project] = fetchFiltered(Project.self)
        let projectTemplates: [ProjectAssignmentTemplate] = fetchFiltered(ProjectAssignmentTemplate.self)
        let projectSessions: [ProjectSession] = fetchFiltered(ProjectSession.self)
        let projectRoles: [ProjectRole] = fetchFiltered(ProjectRole.self)
        let projectWeeks: [ProjectTemplateWeek] = fetchFiltered(ProjectTemplateWeek.self)
        let projectWeekAssignments: [ProjectWeekRoleAssignment] = fetchFiltered(ProjectWeekRoleAssignment.self)

        // Convert to DTOs using shared helpers
        let studentDTOs = BackupServiceHelpers.toDTOs(students)
        let lessonDTOs = BackupServiceHelpers.toDTOs(lessons)
        let legacyPresentationDTOs: [LegacyPresentationDTO] = [] // LegacyPresentation removed
        let noteDTOs = BackupServiceHelpers.toDTOs(notes)
        let nonSchoolDTOs = BackupServiceHelpers.toDTOs(nonSchoolDays)
        let schoolOverrideDTOs = BackupServiceHelpers.toDTOs(schoolDayOverrides)
        let studentMeetingDTOs = BackupServiceHelpers.toDTOs(studentMeetings)
        let topicDTOs = BackupServiceHelpers.toDTOs(communityTopics)
        let solutionDTOs = BackupServiceHelpers.toDTOs(proposedSolutions)
        let attachmentDTOs = BackupServiceHelpers.toDTOs(communityAttachments)
        let attendanceDTOs = BackupServiceHelpers.toDTOs(attendance)
        let workCompletionDTOs = BackupServiceHelpers.toDTOs(workCompletions)
        let projectDTOs = BackupServiceHelpers.toDTOs(projects)
        let projectTemplateDTOs = BackupServiceHelpers.toDTOs(projectTemplates)
        let projectSessionDTOs = BackupServiceHelpers.toDTOs(projectSessions)
        let projectRoleDTOs = BackupServiceHelpers.toDTOs(projectRoles)
        let projectWeekDTOs = BackupServiceHelpers.toDTOs(projectWeeks)
        let projectWeekAssignDTOs = BackupServiceHelpers.toDTOs(projectWeekAssignments)

        let lessonAssignmentDTOs: [LessonAssignmentDTO] = lessonAssignments.map { la in
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

        let preferences = BackupPreferencesService.buildPreferencesDTO()

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            legacyPresentations: legacyPresentationDTOs,
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

        return PayloadCollectionResult(payload: payload, changedCounts: changedCounts, totalCounts: totalCounts)
    }
}
