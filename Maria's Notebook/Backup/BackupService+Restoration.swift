// swiftlint:disable file_length
import Foundation
import CoreData
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
        viewContext: NSManagedObjectContext,
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
            viewContext: viewContext,
            mode: mode,
            entityExists: { [self] type, id in
                do {
                    return (try self.fetchOne(type, id: id, using: viewContext)) != nil
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
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {
        try await importBackup(
            viewContext: viewContext,
            from: url,
            mode: mode,
            password: password,
            appRouter: AppRouter.shared,
            progress: progress
        )
    }

    // Internal version that accepts AppRouter for dependency injection
    func importBackup(
        viewContext: NSManagedObjectContext,
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
            try deleteAll(viewContext: viewContext)
        }

        progress(RestoreProgress.coreEntities, "Importing records\u{2026}")
        try importCoreEntities(from: payload, into: viewContext)
        try importCalendarAndRecordEntities(from: payload, into: viewContext)
        try importProjectEntities(from: payload, into: viewContext)

        progress(RestoreProgress.workTracking, "Importing work tracking\u{2026}")
        try importWorkTrackingEntities(from: payload, into: viewContext)

        progress(RestoreProgress.lessonExtras, "Importing lesson extras\u{2026}")
        try importLessonExtras(from: payload, into: viewContext)

        progress(RestoreProgress.templates, "Importing templates\u{2026}")
        try importTemplateEntities(from: payload, into: viewContext)

        progress(RestoreProgress.tracks, "Importing tracks\u{2026}")
        try importTrackEntities(from: payload, into: viewContext)

        progress(RestoreProgress.documentsSupplies, "Importing documents & supplies\u{2026}")
        try importDocumentEntities(from: payload, into: viewContext)

        progress(RestoreProgress.schedules, "Importing schedules\u{2026}")
        try importScheduleEntities(from: payload, into: viewContext)

        progress(RestoreProgress.issues, "Importing issues\u{2026}")
        try importIssueEntities(from: payload, into: viewContext)

        progress(RestoreProgress.snapshotsTodos, "Importing snapshots & todos\u{2026}")
        try importSnapshotAndTodoEntities(from: payload, into: viewContext)

        progress(RestoreProgress.additionalEntities, "Importing recommendations, resources & links\u{2026}")
        try importAdditionalEntities(from: payload, into: viewContext)
        try importV12Entities(from: payload, into: viewContext)

        progress(RestoreProgress.saving, "Saving\u{2026}")
        try viewContext.save()

        progress(RestoreProgress.denormalizedRepair, "Repairing denormalized fields\u{2026}")
        try repairDenormalizedFields(viewContext: viewContext)

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
        into viewContext: NSManagedObjectContext
    ) throws {
        _ = try BackupEntityImporter.importStudents(
            payload.students,
            into: viewContext,
            existingCheck: { try fetchOne(CDStudent.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importLessons(
            payload.lessons,
            into: viewContext,
            existingCheck: { try fetchOne(CDLesson.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importCommunityTopics(
            payload.communityTopics,
            into: viewContext,
            existingCheck: { try fetchOne(CDCommunityTopicEntity.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importLessonAssignments(
            payload.lessonAssignments,
            into: viewContext,
            existingCheck: { try fetchOne(CDLessonAssignment.self, id: $0, using: viewContext) },
            lessonCheck: { try fetchOne(CDLesson.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importNotes(
            payload.notes,
            into: viewContext,
            existingCheck: { try fetchOne(CDNote.self, id: $0, using: viewContext) },
            lessonCheck: { try fetchOne(CDLesson.self, id: $0, using: viewContext) }
        )
    }

    private func importCalendarAndRecordEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        try BackupEntityImporter.importNonSchoolDays(
            payload.nonSchoolDays,
            into: viewContext,
            existingCheck: { try fetchOne(CDNonSchoolDay.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importSchoolDayOverrides(
            payload.schoolDayOverrides,
            into: viewContext,
            existingCheck: { try fetchOne(CDSchoolDayOverride.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importStudentMeetings(
            payload.studentMeetings,
            into: viewContext,
            existingCheck: { try fetchOne(CDStudentMeeting.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importProposedSolutions(
            payload.proposedSolutions,
            into: viewContext,
            existingCheck: { try fetchOne(ProposedSolution.self, id: $0, using: viewContext) },
            topicCheck: { try fetchOne(CDCommunityTopicEntity.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importCommunityAttachments(
            payload.communityAttachments,
            into: viewContext,
            existingCheck: { try fetchOne(CommunityAttachment.self, id: $0, using: viewContext) },
            topicCheck: { try fetchOne(CDCommunityTopicEntity.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importAttendanceRecords(
            payload.attendance,
            into: viewContext,
            existingCheck: { try fetchOne(CDAttendanceRecord.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importWorkCompletionRecords(
            payload.workCompletions,
            into: viewContext,
            existingCheck: { try fetchOne(CDWorkCompletionRecord.self, id: $0, using: viewContext) }
        )
    }

    private func importProjectEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        try BackupEntityImporter.importProjects(
            payload.projects,
            into: viewContext,
            existingCheck: { try fetchOne(CDProject.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importProjectRoles(
            payload.projectRoles,
            into: viewContext,
            existingCheck: { try fetchOne(ProjectRole.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importProjectTemplateWeeks(
            payload.projectTemplateWeeks,
            into: viewContext,
            existingCheck: { try fetchOne(ProjectTemplateWeek.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importProjectAssignmentTemplates(
            payload.projectAssignmentTemplates,
            into: viewContext,
            existingCheck: { try fetchOne(ProjectAssignmentTemplate.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importProjectWeekRoleAssignments(
            payload.projectWeekRoleAssignments,
            into: viewContext,
            existingCheck: { try fetchOne(ProjectWeekRoleAssignment.self, id: $0, using: viewContext) },
            weekCheck: { try fetchOne(ProjectTemplateWeek.self, id: $0, using: viewContext) }
        )

        try BackupEntityImporter.importProjectSessions(
            payload.projectSessions,
            into: viewContext,
            existingCheck: { try fetchOne(CDProjectSession.self, id: $0, using: viewContext) }
        )
    }

    private func importWorkTrackingEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        // CDWorkModel must be imported first — child entities reference it
        if let workModels = payload.workModels {
            try BackupEntityImporter.importWorkModels(
                workModels,
                into: viewContext,
                existingCheck: { try fetchOne(CDWorkModel.self, id: $0, using: viewContext) }
            )
        }

        if let workCheckIns = payload.workCheckIns {
            try BackupEntityImporter.importWorkCheckIns(
                workCheckIns,
                into: viewContext,
                existingCheck: { try fetchOne(CDWorkCheckIn.self, id: $0, using: viewContext) },
                workCheck: { try fetchOne(CDWorkModel.self, id: $0, using: viewContext) }
            )
        }

        if let workSteps = payload.workSteps {
            try BackupEntityImporter.importWorkSteps(
                workSteps,
                into: viewContext,
                existingCheck: { try fetchOne(CDWorkStep.self, id: $0, using: viewContext) },
                workCheck: { try fetchOne(CDWorkModel.self, id: $0, using: viewContext) }
            )
        }

        if let workParticipants = payload.workParticipants {
            try BackupEntityImporter.importWorkParticipants(
                workParticipants,
                into: viewContext,
                existingCheck: { try fetchOne(WorkParticipantEntity.self, id: $0, using: viewContext) },
                workCheck: { try fetchOne(CDWorkModel.self, id: $0, using: viewContext) }
            )
        }

        if let practiceSessions = payload.practiceSessions {
            try BackupEntityImporter.importPracticeSessions(
                practiceSessions,
                into: viewContext,
                existingCheck: { try fetchOne(CDPracticeSession.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importLessonExtras(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let lessonAttachments = payload.lessonAttachments {
            try BackupEntityImporter.importLessonAttachments(
                lessonAttachments,
                into: viewContext,
                existingCheck: { try fetchOne(LessonAttachment.self, id: $0, using: viewContext) },
                lessonCheck: { try fetchOne(CDLesson.self, id: $0, using: viewContext) }
            )
        }

        if let lessonPresentations = payload.lessonPresentations {
            try BackupEntityImporter.importLessonPresentations(
                lessonPresentations,
                into: viewContext,
                existingCheck: { try fetchOne(CDLessonPresentation.self, id: $0, using: viewContext) }
            )
        }

        if let sampleWorks = payload.sampleWorks {
            try BackupEntityImporter.importSampleWorks(
                sampleWorks,
                into: viewContext,
                existingCheck: { try fetchOne(CDSampleWork.self, id: $0, using: viewContext) },
                lessonCheck: { try fetchOne(CDLesson.self, id: $0, using: viewContext) }
            )
        }

        if let sampleWorkSteps = payload.sampleWorkSteps {
            try BackupEntityImporter.importSampleWorkSteps(
                sampleWorkSteps,
                into: viewContext,
                existingCheck: { try fetchOne(CDSampleWorkStep.self, id: $0, using: viewContext) },
                sampleWorkCheck: { try fetchOne(CDSampleWork.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importTemplateEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let noteTemplates = payload.noteTemplates {
            try BackupEntityImporter.importNoteTemplates(
                noteTemplates,
                into: viewContext,
                existingCheck: { try fetchOne(CDNoteTemplate.self, id: $0, using: viewContext) }
            )
        }

        if let meetingTemplates = payload.meetingTemplates {
            try BackupEntityImporter.importMeetingTemplates(
                meetingTemplates,
                into: viewContext,
                existingCheck: { try fetchOne(CDMeetingTemplate.self, id: $0, using: viewContext) }
            )
        }

        if let reminders = payload.reminders {
            try BackupEntityImporter.importReminders(
                reminders,
                into: viewContext,
                existingCheck: { try fetchOne(CDReminder.self, id: $0, using: viewContext) }
            )
        }

        if let calendarEvents = payload.calendarEvents {
            try BackupEntityImporter.importCalendarEvents(
                calendarEvents,
                into: viewContext,
                existingCheck: { try fetchOne(CDCalendarEvent.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importTrackEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let tracks = payload.tracks {
            try BackupEntityImporter.importTracks(
                tracks,
                into: viewContext,
                existingCheck: { try fetchOne(CDTrackEntity.self, id: $0, using: viewContext) }
            )
        }

        if let trackSteps = payload.trackSteps {
            try BackupEntityImporter.importTrackSteps(
                trackSteps,
                into: viewContext,
                existingCheck: { try fetchOne(TrackStep.self, id: $0, using: viewContext) },
                trackCheck: { try fetchOne(CDTrackEntity.self, id: $0, using: viewContext) }
            )
        }

        if let enrollments = payload.studentTrackEnrollments {
            try BackupEntityImporter.importStudentTrackEnrollments(
                enrollments,
                into: viewContext,
                existingCheck: { try fetchOne(CDStudentTrackEnrollmentEntity.self, id: $0, using: viewContext) }
            )
        }

        if let groupTracks = payload.groupTracks {
            try BackupEntityImporter.importGroupTracks(
                groupTracks,
                into: viewContext,
                existingCheck: { try fetchOne(CDGroupTrack.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importDocumentEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let documents = payload.documents {
            try BackupEntityImporter.importDocuments(
                documents,
                into: viewContext,
                existingCheck: { try fetchOne(CDDocument.self, id: $0, using: viewContext) },
                studentCheck: { try fetchOne(CDStudent.self, id: $0, using: viewContext) }
            )
        }

        if let supplies = payload.supplies {
            try BackupEntityImporter.importSupplies(
                supplies,
                into: viewContext,
                existingCheck: { try fetchOne(CDSupply.self, id: $0, using: viewContext) }
            )
        }

        if let supplyTransactions = payload.supplyTransactions {
            try BackupEntityImporter.importSupplyTransactions(
                supplyTransactions,
                into: viewContext,
                existingCheck: { try fetchOne(SupplyTransaction.self, id: $0, using: viewContext) },
                supplyCheck: { try fetchOne(CDSupply.self, id: $0, using: viewContext) }
            )
        }

        if let procedures = payload.procedures {
            try BackupEntityImporter.importProcedures(
                procedures,
                into: viewContext,
                existingCheck: { try fetchOne(CDProcedure.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importScheduleEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let schedules = payload.schedules {
            try BackupEntityImporter.importSchedules(
                schedules,
                into: viewContext,
                existingCheck: { try fetchOne(CDSchedule.self, id: $0, using: viewContext) }
            )
        }

        if let scheduleSlots = payload.scheduleSlots {
            try BackupEntityImporter.importScheduleSlots(
                scheduleSlots,
                into: viewContext,
                existingCheck: { try fetchOne(CDScheduleSlot.self, id: $0, using: viewContext) },
                scheduleCheck: { try fetchOne(CDSchedule.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importIssueEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let issues = payload.issues {
            try BackupEntityImporter.importIssues(
                issues,
                into: viewContext,
                existingCheck: { try fetchOne(CDIssue.self, id: $0, using: viewContext) }
            )
        }

        if let issueActions = payload.issueActions {
            try BackupEntityImporter.importIssueActions(
                issueActions,
                into: viewContext,
                existingCheck: { try fetchOne(IssueAction.self, id: $0, using: viewContext) },
                issueCheck: { try fetchOne(CDIssue.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importSnapshotAndTodoEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let snapshots = payload.developmentSnapshots {
            try BackupEntityImporter.importDevelopmentSnapshots(
                snapshots,
                into: viewContext,
                existingCheck: { try fetchOne(DevelopmentSnapshot.self, id: $0, using: viewContext) }
            )
        }

        if let todoItems = payload.todoItems {
            try BackupEntityImporter.importTodoItems(
                todoItems,
                into: viewContext,
                existingCheck: { try fetchOne(CDTodoItem.self, id: $0, using: viewContext) }
            )
        }

        if let todoSubtasks = payload.todoSubtasks {
            try BackupEntityImporter.importTodoSubtasks(
                todoSubtasks,
                into: viewContext,
                existingCheck: { try fetchOne(CDTodoSubtask.self, id: $0, using: viewContext) },
                todoCheck: { try fetchOne(CDTodoItem.self, id: $0, using: viewContext) }
            )
        }

        if let todoTemplates = payload.todoTemplates {
            try BackupEntityImporter.importTodoTemplates(
                todoTemplates,
                into: viewContext,
                existingCheck: { try fetchOne(CDTodoTemplate.self, id: $0, using: viewContext) }
            )
        }

        if let agendaOrders = payload.todayAgendaOrders {
            try BackupEntityImporter.importTodayAgendaOrders(
                agendaOrders,
                into: viewContext,
                existingCheck: { try fetchOne(CDTodayAgendaOrder.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importAdditionalEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let recommendations = payload.planningRecommendations {
            try BackupEntityImporter.importPlanningRecommendations(
                recommendations,
                into: viewContext,
                existingCheck: { try fetchOne(PlanningRecommendation.self, id: $0, using: viewContext) }
            )
        }

        if let resources = payload.resources {
            try BackupEntityImporter.importResources(
                resources,
                into: viewContext,
                existingCheck: { try fetchOne(CDResource.self, id: $0, using: viewContext) }
            )
        }

        if let noteStudentLinks = payload.noteStudentLinks {
            try BackupEntityImporter.importNoteStudentLinks(
                noteStudentLinks,
                into: viewContext,
                existingCheck: { try fetchOne(CDNoteStudentLink.self, id: $0, using: viewContext) },
                noteCheck: { try fetchOne(CDNote.self, id: $0, using: viewContext) }
            )
        }
    }

    private func importV12Entities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext
    ) throws {
        if let goingOuts = payload.goingOuts {
            try BackupEntityImporter.importGoingOuts(
                goingOuts,
                into: viewContext,
                existingCheck: { try fetchOne(CDGoingOut.self, id: $0, using: viewContext) }
            )
        }

        if let goingOutItems = payload.goingOutChecklistItems {
            try BackupEntityImporter.importGoingOutChecklistItems(
                goingOutItems,
                into: viewContext,
                existingCheck: { try fetchOne(GoingOutChecklistItem.self, id: $0, using: viewContext) },
                goingOutCheck: { try fetchOne(CDGoingOut.self, id: $0, using: viewContext) }
            )
        }

        if let classroomJobs = payload.classroomJobs {
            try BackupEntityImporter.importClassroomJobs(
                classroomJobs,
                into: viewContext,
                existingCheck: { try fetchOne(CDClassroomJob.self, id: $0, using: viewContext) }
            )
        }

        if let jobAssignments = payload.jobAssignments {
            try BackupEntityImporter.importJobAssignments(
                jobAssignments,
                into: viewContext,
                existingCheck: { try fetchOne(CDJobAssignment.self, id: $0, using: viewContext) },
                jobCheck: { try fetchOne(CDClassroomJob.self, id: $0, using: viewContext) }
            )
        }

        if let transitionPlans = payload.transitionPlans {
            try BackupEntityImporter.importTransitionPlans(
                transitionPlans,
                into: viewContext,
                existingCheck: { try fetchOne(CDTransitionPlan.self, id: $0, using: viewContext) }
            )
        }

        if let transitionItems = payload.transitionChecklistItems {
            try BackupEntityImporter.importTransitionChecklistItems(
                transitionItems,
                into: viewContext,
                existingCheck: { try fetchOne(TransitionChecklistItem.self, id: $0, using: viewContext) },
                planCheck: { try fetchOne(CDTransitionPlan.self, id: $0, using: viewContext) }
            )
        }

        if let calendarNotes = payload.calendarNotes {
            try BackupEntityImporter.importCalendarNotes(
                calendarNotes,
                into: viewContext,
                existingCheck: { try fetchOne(CDCalendarNote.self, id: $0, using: viewContext) }
            )
        }

        if let scheduledMeetings = payload.scheduledMeetings {
            try BackupEntityImporter.importScheduledMeetings(
                scheduledMeetings,
                into: viewContext,
                existingCheck: { try fetchOne(CDScheduledMeeting.self, id: $0, using: viewContext) }
            )
        }

        if let albumOrders = payload.albumGroupOrders {
            try BackupEntityImporter.importAlbumGroupOrders(
                albumOrders,
                into: viewContext,
                existingCheck: { try fetchOne(AlbumGroupOrder.self, id: $0, using: viewContext) }
            )
        }

        if let albumStates = payload.albumGroupUIStates {
            try BackupEntityImporter.importAlbumGroupUIStates(
                albumStates,
                into: viewContext,
                existingCheck: { try fetchOne(AlbumGroupUIState.self, id: $0, using: viewContext) }
            )
        }

        // v13+ entities
        if let memberships = payload.classroomMemberships {
            try BackupEntityImporter.importClassroomMemberships(
                memberships,
                into: viewContext,
                existingCheck: { try fetchOne(CDClassroomMembership.self, id: $0, using: viewContext) }
            )
        }
    }

    private func repairDenormalizedFields(viewContext: NSManagedObjectContext) throws {
        let assignmentsForRepair = try viewContext.fetch(CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>)
        var repairedCount = 0
        for la in assignmentsForRepair {
            let correct = la.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if la.scheduledForDay != correct {
                la.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try viewContext.save()
        }
    }
}
