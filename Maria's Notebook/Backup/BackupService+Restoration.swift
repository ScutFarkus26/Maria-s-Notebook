import Foundation
import SwiftData
import SwiftUI

// MARK: - Restore Preview & Import

extension BackupService {

    // MARK: - Restore Preview
    public func previewImport(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> RestorePreview {

        let (_, payload) = try withSecurityScopedResource(url) {
            try loadAndDecodeBackup(from: url, password: password, progress: progress)
        }

        progress(0.50, "Analyzing\u{2026}")

        // Use BackupPreviewAnalyzer to compute insert/skip/delete counts
        let analysis = BackupPreviewAnalyzer.analyze(
            payload: payload,
            modelContext: modelContext,
            mode: mode,
            entityExists: { [self] type, id in
                do {
                    return (try self.fetchOne(type, id: id, using: modelContext)) != nil
                } catch {
                    // swiftlint:disable:next line_length
                    print("\u{26a0}\u{fe0f} [BackupService] Failed to check entity existence for type \(String(describing: type)): \(error)")
                    return false
                }
            }
        )

        progress(1.0, "Done")
        return RestorePreview(
            mode: mode.rawValue,
            entityInserts: analysis.inserts,
            entitySkips: analysis.skips,
            entityDeletes: analysis.deletes,
            totalInserts: analysis.totalInserts,
            totalDeletes: analysis.totalDeletes,
            warnings: analysis.warnings
        )
    }

    // MARK: - Import
    public func importBackup(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {
        try await importBackup(
            modelContext: modelContext,
            from: url,
            mode: mode,
            password: password,
            appRouter: AppRouter.shared,
            progress: progress
        )
    }

    // Internal version that accepts AppRouter for dependency injection
    func importBackup(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        appRouter: AppRouter,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {

        let (envelope, loadedPayload) = try withSecurityScopedResource(url) {
            try loadAndDecodeBackup(from: url, password: password, progress: progress)
        }

        var payload = loadedPayload

        // Deduplicate payload arrays instead of failing on duplicates
        // This handles backups that were created before deduplication was added,
        // or backups from CloudKit-synced databases that had duplicate records
        progress(0.35, "Deduplicating records\u{2026}")
        payload = deduplicatePayload(payload)

        if mode == .replace {
            progress(0.40, "Clearing existing data\u{2026}")
            appRouter.signalAppDataWillBeReplaced()
            try deleteAll(modelContext: modelContext)
        }

        progress(0.65, "Importing records\u{2026}")

        // Import all entities using BackupEntityImporter
        // Note: fetchOne is passed as a closure to avoid storing ModelContext in the importer
        _ = try BackupEntityImporter.importStudents(
            payload.students,
            into: modelContext,
            existingCheck: { try fetchOne(Student.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importLessons(
            payload.lessons,
            into: modelContext,
            existingCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importCommunityTopics(
            payload.communityTopics,
            into: modelContext,
            existingCheck: { try fetchOne(CommunityTopic.self, id: $0, using: modelContext) }
        )

        // Import old LegacyPresentationDTOs as LessonAssignment records
        try BackupEntityImporter.importLegacyPresentations(
            payload.legacyPresentations,
            into: modelContext,
            existingCheck: { try fetchOne(LessonAssignment.self, id: $0, using: modelContext) },
            lessonCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) },
            studentCheck: { try fetchOne(Student.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importLessonAssignments(
            payload.lessonAssignments,
            into: modelContext,
            existingCheck: { try fetchOne(LessonAssignment.self, id: $0, using: modelContext) },
            lessonCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importNotes(
            payload.notes,
            into: modelContext,
            existingCheck: { try fetchOne(Note.self, id: $0, using: modelContext) },
            lessonCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importNonSchoolDays(
            payload.nonSchoolDays,
            into: modelContext,
            existingCheck: { try fetchOne(NonSchoolDay.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importSchoolDayOverrides(
            payload.schoolDayOverrides,
            into: modelContext,
            existingCheck: { try fetchOne(SchoolDayOverride.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importStudentMeetings(
            payload.studentMeetings,
            into: modelContext,
            existingCheck: { try fetchOne(StudentMeeting.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProposedSolutions(
            payload.proposedSolutions,
            into: modelContext,
            existingCheck: { try fetchOne(ProposedSolution.self, id: $0, using: modelContext) },
            topicCheck: { try fetchOne(CommunityTopic.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importCommunityAttachments(
            payload.communityAttachments,
            into: modelContext,
            existingCheck: { try fetchOne(CommunityAttachment.self, id: $0, using: modelContext) },
            topicCheck: { try fetchOne(CommunityTopic.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importAttendanceRecords(
            payload.attendance,
            into: modelContext,
            existingCheck: { try fetchOne(AttendanceRecord.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importWorkCompletionRecords(
            payload.workCompletions,
            into: modelContext,
            existingCheck: { try fetchOne(WorkCompletionRecord.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProjects(
            payload.projects,
            into: modelContext,
            existingCheck: { try fetchOne(Project.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProjectRoles(
            payload.projectRoles,
            into: modelContext,
            existingCheck: { try fetchOne(ProjectRole.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProjectTemplateWeeks(
            payload.projectTemplateWeeks,
            into: modelContext,
            existingCheck: { try fetchOne(ProjectTemplateWeek.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProjectAssignmentTemplates(
            payload.projectAssignmentTemplates,
            into: modelContext,
            existingCheck: { try fetchOne(ProjectAssignmentTemplate.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProjectWeekRoleAssignments(
            payload.projectWeekRoleAssignments,
            into: modelContext,
            existingCheck: { try fetchOne(ProjectWeekRoleAssignment.self, id: $0, using: modelContext) },
            weekCheck: { try fetchOne(ProjectTemplateWeek.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importProjectSessions(
            payload.projectSessions,
            into: modelContext,
            existingCheck: { try fetchOne(ProjectSession.self, id: $0, using: modelContext) }
        )

        // Format v8+ entities (nil-safe for older backups)
        progress(0.70, "Importing work tracking\u{2026}")

        if let workCheckIns = payload.workCheckIns {
            try BackupEntityImporter.importWorkCheckIns(
                workCheckIns,
                into: modelContext,
                existingCheck: { try fetchOne(WorkCheckIn.self, id: $0, using: modelContext) },
                workCheck: { try fetchOne(WorkModel.self, id: $0, using: modelContext) }
            )
        }

        if let workSteps = payload.workSteps {
            try BackupEntityImporter.importWorkSteps(
                workSteps,
                into: modelContext,
                existingCheck: { try fetchOne(WorkStep.self, id: $0, using: modelContext) },
                workCheck: { try fetchOne(WorkModel.self, id: $0, using: modelContext) }
            )
        }

        if let workParticipants = payload.workParticipants {
            try BackupEntityImporter.importWorkParticipants(
                workParticipants,
                into: modelContext,
                existingCheck: { try fetchOne(WorkParticipantEntity.self, id: $0, using: modelContext) },
                workCheck: { try fetchOne(WorkModel.self, id: $0, using: modelContext) }
            )
        }

        if let practiceSessions = payload.practiceSessions {
            try BackupEntityImporter.importPracticeSessions(
                practiceSessions,
                into: modelContext,
                existingCheck: { try fetchOne(PracticeSession.self, id: $0, using: modelContext) }
            )
        }

        progress(0.74, "Importing lesson extras\u{2026}")

        if let lessonAttachments = payload.lessonAttachments {
            try BackupEntityImporter.importLessonAttachments(
                lessonAttachments,
                into: modelContext,
                existingCheck: { try fetchOne(LessonAttachment.self, id: $0, using: modelContext) },
                lessonCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) }
            )
        }

        if let lessonPresentations = payload.lessonPresentations {
            try BackupEntityImporter.importLessonPresentations(
                lessonPresentations,
                into: modelContext,
                existingCheck: { try fetchOne(LessonPresentation.self, id: $0, using: modelContext) }
            )
        }

        if let sampleWorks = payload.sampleWorks {
            try BackupEntityImporter.importSampleWorks(
                sampleWorks,
                into: modelContext,
                existingCheck: { try fetchOne(SampleWork.self, id: $0, using: modelContext) },
                lessonCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) }
            )
        }

        if let sampleWorkSteps = payload.sampleWorkSteps {
            try BackupEntityImporter.importSampleWorkSteps(
                sampleWorkSteps,
                into: modelContext,
                existingCheck: { try fetchOne(SampleWorkStep.self, id: $0, using: modelContext) },
                sampleWorkCheck: { try fetchOne(SampleWork.self, id: $0, using: modelContext) }
            )
        }

        progress(0.76, "Importing templates\u{2026}")

        if let noteTemplates = payload.noteTemplates {
            try BackupEntityImporter.importNoteTemplates(
                noteTemplates,
                into: modelContext,
                existingCheck: { try fetchOne(NoteTemplate.self, id: $0, using: modelContext) }
            )
        }

        if let meetingTemplates = payload.meetingTemplates {
            try BackupEntityImporter.importMeetingTemplates(
                meetingTemplates,
                into: modelContext,
                existingCheck: { try fetchOne(MeetingTemplate.self, id: $0, using: modelContext) }
            )
        }

        if let reminders = payload.reminders {
            try BackupEntityImporter.importReminders(
                reminders,
                into: modelContext,
                existingCheck: { try fetchOne(Reminder.self, id: $0, using: modelContext) }
            )
        }

        if let calendarEvents = payload.calendarEvents {
            try BackupEntityImporter.importCalendarEvents(
                calendarEvents,
                into: modelContext,
                existingCheck: { try fetchOne(CalendarEvent.self, id: $0, using: modelContext) }
            )
        }

        progress(0.78, "Importing tracks\u{2026}")

        if let tracks = payload.tracks {
            try BackupEntityImporter.importTracks(
                tracks,
                into: modelContext,
                existingCheck: { try fetchOne(Track.self, id: $0, using: modelContext) }
            )
        }

        if let trackSteps = payload.trackSteps {
            try BackupEntityImporter.importTrackSteps(
                trackSteps,
                into: modelContext,
                existingCheck: { try fetchOne(TrackStep.self, id: $0, using: modelContext) },
                trackCheck: { try fetchOne(Track.self, id: $0, using: modelContext) }
            )
        }

        if let enrollments = payload.studentTrackEnrollments {
            try BackupEntityImporter.importStudentTrackEnrollments(
                enrollments,
                into: modelContext,
                existingCheck: { try fetchOne(StudentTrackEnrollment.self, id: $0, using: modelContext) }
            )
        }

        if let groupTracks = payload.groupTracks {
            try BackupEntityImporter.importGroupTracks(
                groupTracks,
                into: modelContext,
                existingCheck: { try fetchOne(GroupTrack.self, id: $0, using: modelContext) }
            )
        }

        progress(0.80, "Importing documents & supplies\u{2026}")

        if let documents = payload.documents {
            try BackupEntityImporter.importDocuments(
                documents,
                into: modelContext,
                existingCheck: { try fetchOne(Document.self, id: $0, using: modelContext) },
                studentCheck: { try fetchOne(Student.self, id: $0, using: modelContext) }
            )
        }

        if let supplies = payload.supplies {
            try BackupEntityImporter.importSupplies(
                supplies,
                into: modelContext,
                existingCheck: { try fetchOne(Supply.self, id: $0, using: modelContext) }
            )
        }

        if let supplyTransactions = payload.supplyTransactions {
            try BackupEntityImporter.importSupplyTransactions(
                supplyTransactions,
                into: modelContext,
                existingCheck: { try fetchOne(SupplyTransaction.self, id: $0, using: modelContext) },
                supplyCheck: { try fetchOne(Supply.self, id: $0, using: modelContext) }
            )
        }

        if let procedures = payload.procedures {
            try BackupEntityImporter.importProcedures(
                procedures,
                into: modelContext,
                existingCheck: { try fetchOne(Procedure.self, id: $0, using: modelContext) }
            )
        }

        progress(0.82, "Importing schedules\u{2026}")

        if let schedules = payload.schedules {
            try BackupEntityImporter.importSchedules(
                schedules,
                into: modelContext,
                existingCheck: { try fetchOne(Schedule.self, id: $0, using: modelContext) }
            )
        }

        if let scheduleSlots = payload.scheduleSlots {
            try BackupEntityImporter.importScheduleSlots(
                scheduleSlots,
                into: modelContext,
                existingCheck: { try fetchOne(ScheduleSlot.self, id: $0, using: modelContext) },
                scheduleCheck: { try fetchOne(Schedule.self, id: $0, using: modelContext) }
            )
        }

        progress(0.84, "Importing issues\u{2026}")

        if let issues = payload.issues {
            try BackupEntityImporter.importIssues(
                issues,
                into: modelContext,
                existingCheck: { try fetchOne(Issue.self, id: $0, using: modelContext) }
            )
        }

        if let issueActions = payload.issueActions {
            try BackupEntityImporter.importIssueActions(
                issueActions,
                into: modelContext,
                existingCheck: { try fetchOne(IssueAction.self, id: $0, using: modelContext) },
                issueCheck: { try fetchOne(Issue.self, id: $0, using: modelContext) }
            )
        }

        progress(0.86, "Importing snapshots & todos\u{2026}")

        if let snapshots = payload.developmentSnapshots {
            try BackupEntityImporter.importDevelopmentSnapshots(
                snapshots,
                into: modelContext,
                existingCheck: { try fetchOne(DevelopmentSnapshot.self, id: $0, using: modelContext) }
            )
        }

        if let todoItems = payload.todoItems {
            try BackupEntityImporter.importTodoItems(
                todoItems,
                into: modelContext,
                existingCheck: { try fetchOne(TodoItem.self, id: $0, using: modelContext) }
            )
        }

        if let todoSubtasks = payload.todoSubtasks {
            try BackupEntityImporter.importTodoSubtasks(
                todoSubtasks,
                into: modelContext,
                existingCheck: { try fetchOne(TodoSubtask.self, id: $0, using: modelContext) },
                todoCheck: { try fetchOne(TodoItem.self, id: $0, using: modelContext) }
            )
        }

        if let todoTemplates = payload.todoTemplates {
            try BackupEntityImporter.importTodoTemplates(
                todoTemplates,
                into: modelContext,
                existingCheck: { try fetchOne(TodoTemplate.self, id: $0, using: modelContext) }
            )
        }

        if let agendaOrders = payload.todayAgendaOrders {
            try BackupEntityImporter.importTodayAgendaOrders(
                agendaOrders,
                into: modelContext,
                existingCheck: { try fetchOne(TodayAgendaOrder.self, id: $0, using: modelContext) }
            )
        }

        progress(0.90, "Saving\u{2026}")
        try modelContext.save()

        progress(0.92, "Repairing denormalized fields\u{2026}")
        let assignmentsForRepair = try modelContext.fetch(FetchDescriptor<LessonAssignment>())
        var repairedCount = 0
        for la in assignmentsForRepair {
            let correct = la.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if la.scheduledForDay != correct {
                la.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try modelContext.save()
        }

        applyPreferencesDTO(payload.preferences)
        appRouter.signalAppDataDidRestore()

        let counts = envelope.manifest.entityCounts
        progress(1.0, "Done")
        return BackupOperationSummary(
            kind: .import,
            fileName: url.lastPathComponent,
            formatVersion: envelope.formatVersion,
            encryptUsed: envelope.payload == nil,
            createdAt: envelope.createdAt,
            entityCounts: counts,
            warnings: []
        )
    }
}
