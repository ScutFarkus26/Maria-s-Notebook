// swiftlint:disable file_length
import Foundation
import SwiftData
import SwiftUI
import OSLog

// MARK: - Import Progress Steps

/// Named progress milestones for backup restoration, replacing inline magic numbers.
/// Each value corresponds to the fraction-complete reported to the caller's ProgressCallback.
private enum RestoreProgress {
    static let deduplication: Double = 0.35
    static let clearing: Double = 0.40
    static let coreEntities: Double = 0.65
    static let workTracking: Double = 0.70
    static let lessonExtras: Double = 0.74
    static let templates: Double = 0.76
    static let tracks: Double = 0.78
    static let documentsSupplies: Double = 0.80
    static let schedules: Double = 0.82
    static let issues: Double = 0.84
    static let snapshotsTodos: Double = 0.86
    static let additionalEntities: Double = 0.88
    static let saving: Double = 0.90
    static let denormalizedRepair: Double = 0.92
    static let done: Double = 1.00
}

// MARK: - Restore Preview & Import

extension BackupService {
    private static let logger = Logger.backup

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

        progress(0.50, "Analyzing\u{2026}") // preview analysis: fixed midpoint

        // Use BackupPreviewAnalyzer to compute insert/skip/delete counts
        let analysis = BackupPreviewAnalyzer.analyze(
            payload: payload,
            modelContext: modelContext,
            mode: mode,
            entityExists: { [self] type, id in
                do {
                    return (try self.fetchOne(type, id: id, using: modelContext)) != nil
                } catch {
                    let typeName = String(describing: type)
                    let desc = error.localizedDescription
                    Self.logger.warning(
                        "Entity existence check failed for \(typeName, privacy: .public): \(desc, privacy: .public)"
                    )
                    return false
                }
            }
        )

        progress(RestoreProgress.done, "Done")
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
        progress(RestoreProgress.deduplication, "Deduplicating records\u{2026}")
        payload = deduplicatePayload(payload)

        if mode == .replace {
            progress(RestoreProgress.clearing, "Clearing existing data\u{2026}")
            appRouter.signalAppDataWillBeReplaced()
            try deleteAll(modelContext: modelContext)
        }

        progress(RestoreProgress.coreEntities, "Importing records\u{2026}")
        try importCoreEntities(from: payload, into: modelContext)
        try importCalendarAndRecordEntities(from: payload, into: modelContext)
        try importProjectEntities(from: payload, into: modelContext)

        progress(RestoreProgress.workTracking, "Importing work tracking\u{2026}")
        try importWorkTrackingEntities(from: payload, into: modelContext)

        progress(RestoreProgress.lessonExtras, "Importing lesson extras\u{2026}")
        try importLessonExtras(from: payload, into: modelContext)

        progress(RestoreProgress.templates, "Importing templates\u{2026}")
        try importTemplateEntities(from: payload, into: modelContext)

        progress(RestoreProgress.tracks, "Importing tracks\u{2026}")
        try importTrackEntities(from: payload, into: modelContext)

        progress(RestoreProgress.documentsSupplies, "Importing documents & supplies\u{2026}")
        try importDocumentEntities(from: payload, into: modelContext)

        progress(RestoreProgress.schedules, "Importing schedules\u{2026}")
        try importScheduleEntities(from: payload, into: modelContext)

        progress(RestoreProgress.issues, "Importing issues\u{2026}")
        try importIssueEntities(from: payload, into: modelContext)

        progress(RestoreProgress.snapshotsTodos, "Importing snapshots & todos\u{2026}")
        try importSnapshotAndTodoEntities(from: payload, into: modelContext)

        progress(RestoreProgress.additionalEntities, "Importing recommendations, resources & links\u{2026}")
        try importAdditionalEntities(from: payload, into: modelContext)

        progress(RestoreProgress.saving, "Saving\u{2026}")
        try modelContext.save()

        progress(RestoreProgress.denormalizedRepair, "Repairing denormalized fields\u{2026}")
        try repairDenormalizedFields(modelContext: modelContext)

        applyPreferencesDTO(payload.preferences)
        appRouter.signalAppDataDidRestore()

        let counts = envelope.manifest.entityCounts
        progress(RestoreProgress.done, "Done")
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

    // MARK: - Import Helpers

    private func importCoreEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importCalendarAndRecordEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importProjectEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importWorkTrackingEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
        // WorkModel must be imported first — child entities reference it
        if let workModels = payload.workModels {
            try BackupEntityImporter.importWorkModels(
                workModels,
                into: modelContext,
                existingCheck: { try fetchOne(WorkModel.self, id: $0, using: modelContext) }
            )
        }

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
    }

    private func importLessonExtras(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importTemplateEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importTrackEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importDocumentEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importScheduleEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importIssueEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importSnapshotAndTodoEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
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
    }

    private func importAdditionalEntities(
        from payload: BackupPayload,
        into modelContext: ModelContext
    ) throws {
        if let recommendations = payload.planningRecommendations {
            try BackupEntityImporter.importPlanningRecommendations(
                recommendations,
                into: modelContext,
                existingCheck: { try fetchOne(PlanningRecommendation.self, id: $0, using: modelContext) }
            )
        }

        if let resources = payload.resources {
            try BackupEntityImporter.importResources(
                resources,
                into: modelContext,
                existingCheck: { try fetchOne(Resource.self, id: $0, using: modelContext) }
            )
        }

        if let noteStudentLinks = payload.noteStudentLinks {
            try BackupEntityImporter.importNoteStudentLinks(
                noteStudentLinks,
                into: modelContext,
                existingCheck: { try fetchOne(NoteStudentLink.self, id: $0, using: modelContext) },
                noteCheck: { try fetchOne(Note.self, id: $0, using: modelContext) }
            )
        }
    }

    private func repairDenormalizedFields(modelContext: ModelContext) throws {
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
    }
}
