// swiftlint:disable file_length
import Foundation
import CoreData
import SwiftUI
import OSLog

// MARK: - Restore Errors

/// Error thrown when a `.replace` restore cannot fully clear existing data.
/// It propagates through `BackupTransactionManager.executeWithRollback`, which
/// rolls back to the safety checkpoint — returning the user to their pre-restore
/// state instead of leaving a half-cleared store.
private enum RestoreClearError: LocalizedError {
    case replaceClearIncomplete([String])

    var errorDescription: String? {
        switch self {
        case .replaceClearIncomplete(let names):
            return "Restore was stopped because existing \(names.joined(separator: ", ")) "
                + "could not be cleared. Your data was returned to its previous state \u{2014} please try again."
        }
    }
}

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
    static let cloudSync: Double = 0.96
    static let done: Double = 1.00
}

/// Outcome of waiting for `NSPersistentCloudKitContainer` to finish the post-restore export.
enum CloudExportWaitResult: Sendable {
    /// No CloudKit-backed store, or the wait completed and a `.export` event succeeded.
    case completed
    /// `.export` event arrived but reported `succeeded == false`. Carries a localized description
    /// (not the underlying `Error` — `any Error` doesn't cross task boundaries cleanly).
    case failed(reason: String?)
    /// Timed out before any complete `.export` event arrived. Sync is still running in the background.
    case timedOut
}

// MARK: - Restore Preview & Import

extension BackupService {
    private static let logger = Logger.backup

    // swiftlint:disable:next function_parameter_count function_body_length
    /// Post-decode import path. Shared by:
    ///   - `BackupCoordinator` for archive imports (which reconstructs
    ///     a `BackupPayload` from archive entries then calls this)
    /// Centralizing this method means deleteAll, the entity-import dispatch,
    /// the denormalized-field repair, and the CloudKit-sync wait all share one
    /// code path across format versions.
    func importPayload(
        payload loadedPayload: BackupPayload,
        envelopeFormatVersion: Int,
        envelopeEncrypted: Bool,
        envelopeCreatedAt: Date,
        envelopeFileName: String,
        envelopeEntityCounts: [String: Int],
        viewContext: NSManagedObjectContext,
        mode: RestoreMode,
        appRouter: AppRouter,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {

        var payload = loadedPayload
        progress(RestoreProgress.deduplication, "Deduplicating records\u{2026}")
        payload = deduplicatePayload(payload)

        if mode == .replace {
            progress(RestoreProgress.clearing, "Clearing existing data\u{2026}")
            appRouter.signalAppDataWillBeReplaced()
            let failedEntities = try deleteAll(viewContext: viewContext)
            if !failedEntities.isEmpty {
                // Replace mode must fully clear the store before importing. If some
                // types couldn't be cleared, abort so the transaction manager rolls
                // back to the safety checkpoint instead of importing on top of a
                // half-cleared store. The checkpoint is guaranteed for .replace, so
                // the user is returned to their pre-restore state.
                throw RestoreClearError.replaceClearIncomplete(failedEntities)
            }
        }

        // One fetch per entity type instead of one fetch per record. Built
        // lazily so child-type lookups see parents inserted earlier in this
        // same restore (see BackupEntityIndex).
        let index = BackupEntityIndex(context: viewContext)

        progress(RestoreProgress.coreEntities, "Importing records\u{2026}")
        try importCoreEntities(from: payload, into: viewContext, index: index)
        try importCalendarAndRecordEntities(from: payload, into: viewContext, index: index)
        try importProjectEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.workTracking, "Importing work tracking\u{2026}")
        try importWorkTrackingEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.lessonExtras, "Importing lesson extras\u{2026}")
        try importLessonExtras(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.templates, "Importing templates\u{2026}")
        try importTemplateEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.tracks, "Importing tracks\u{2026}")
        try importTrackEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.documentsSupplies, "Importing documents & supplies\u{2026}")
        try importDocumentEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.schedules, "Importing schedules\u{2026}")
        try importScheduleEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.issues, "Importing issues\u{2026}")
        try importIssueEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.snapshotsTodos, "Importing snapshots & todos\u{2026}")
        try importSnapshotAndTodoEntities(from: payload, into: viewContext, index: index)

        progress(RestoreProgress.additionalEntities, "Importing recommendations, resources & links\u{2026}")
        try importAdditionalEntities(from: payload, into: viewContext, index: index)
        try importV12Entities(from: payload, into: viewContext, index: index)
        try importV18Entities(from: payload, into: viewContext, index: index)

        // Notes import early, but many of their relationship targets (work,
        // check-ins, meetings, etc.) import in later phases — relink them now
        // that every target type is in the store.
        try BackupEntityImporter.relinkNoteRelationships(payload.notes, index: index)

        // Subscribe to CloudKit export events BEFORE saving — a fast export
        // could otherwise complete between save() and subscription, leaving
        // the user staring at a 30-second timeout for an event that already
        // fired.
        let cloudExportWait = Task {
            await awaitCloudKitExport(viewContext: viewContext, timeout: .seconds(30))
        }
        defer { cloudExportWait.cancel() }

        progress(RestoreProgress.saving, "Saving\u{2026}")
        try viewContext.save()

        progress(RestoreProgress.denormalizedRepair, "Repairing denormalized fields\u{2026}")
        try repairDenormalizedFields(viewContext: viewContext)

        applyPreferencesDTO(payload.preferences)
        appRouter.signalAppDataDidRestore()

        // After save, the in-memory model is correct but CloudKit-mirrored stores still need
        // to upload the new records. Block briefly so users see a definitive "synced" message
        // when possible; on timeout, surface that sync is continuing in the background.
        progress(RestoreProgress.cloudSync, "Syncing to iCloud\u{2026}")
        let cloudResult = await cloudExportWait.value

        var warnings: [String] = []
        switch cloudResult {
        case .completed:
            break
        case .failed(let reason):
            let detail = reason ?? "unknown error"
            warnings.append(
                "iCloud sync reported a failure: \(detail). " +
                "Your data is saved locally; check Settings → iCloud to retry."
            )
        case .timedOut:
            warnings.append(
                "iCloud sync is still running in the background. " +
                "Keep the app open for a moment to finish uploading."
            )
        }

        progress(RestoreProgress.done, "Done")
        return BackupOperationSummary(
            kind: .import,
            fileName: envelopeFileName,
            formatVersion: envelopeFormatVersion,
            encryptUsed: envelopeEncrypted,
            createdAt: envelopeCreatedAt,
            entityCounts: envelopeEntityCounts,
            warnings: warnings
        )
    }

    // MARK: - CloudKit Export Wait

    /// Waits for an `NSPersistentCloudKitContainer` `.export` event to complete after a restore.
    /// Returns immediately if no CloudKit-backed store is attached (e.g., test in-memory stack).
    private func awaitCloudKitExport(
        viewContext: NSManagedObjectContext,
        timeout: Duration
    ) async -> CloudExportWaitResult {
        // Skip the wait when there's no CloudKit-mirrored store (in-memory tests, local-only fallback).
        guard isCloudKitMirrored(viewContext: viewContext) else { return .completed }

        let stream = NotificationCenter.default.notifications(
            named: NSPersistentCloudKitContainer.eventChangedNotification
        )

        return await withTaskGroup(of: CloudExportWaitResult.self) { group in
            group.addTask {
                for await notification in stream {
                    guard let event = notification.userInfo?[
                        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    ] as? NSPersistentCloudKitContainer.Event else { continue }
                    guard event.type == .export, event.endDate != nil else { continue }
                    if event.succeeded {
                        return .completed
                    } else {
                        return .failed(reason: event.error?.localizedDescription)
                    }
                }
                return .timedOut
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    /// True when `viewContext` is attached to at least one CloudKit-mirrored persistent store.
    /// Detects the in-memory test stack and skips the export wait.
    private func isCloudKitMirrored(viewContext: NSManagedObjectContext) -> Bool {
        guard let stores = viewContext.persistentStoreCoordinator?.persistentStores else { return false }
        for store in stores {
            if store.type == NSInMemoryStoreType { continue }
            // Any non-memory SQLite store in this app is CloudKit-mirrored by configuration.
            if store.type == NSSQLiteStoreType { return true }
        }
        return false
    }

    // MARK: - Import Helpers

    private func importCoreEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        _ = try BackupEntityImporter.importStudents(
            payload.students,
            into: viewContext,
            existingCheck: { try index.exists(CDStudent.self, id: $0) }
        )

        try BackupEntityImporter.importLessons(
            payload.lessons,
            into: viewContext,
            existingCheck: { try index.exists(CDLesson.self, id: $0) }
        )

        try BackupEntityImporter.importCommunityTopics(
            payload.communityTopics,
            into: viewContext,
            existingCheck: { try index.exists(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importLessonAssignments(
            payload.lessonAssignments,
            into: viewContext,
            existingCheck: { try index.exists(CDLessonAssignment.self, id: $0) },
            lessonCheck: { try index.related(CDLesson.self, id: $0) }
        )

        try BackupEntityImporter.importNotes(
            payload.notes,
            into: viewContext,
            existingCheck: { try index.exists(CDNote.self, id: $0) }
        )
    }

    private func importCalendarAndRecordEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        try BackupEntityImporter.importNonSchoolDays(
            payload.nonSchoolDays,
            into: viewContext,
            existingCheck: { try index.exists(CDNonSchoolDay.self, id: $0) }
        )

        try BackupEntityImporter.importSchoolDayOverrides(
            payload.schoolDayOverrides,
            into: viewContext,
            existingCheck: { try index.exists(CDSchoolDayOverride.self, id: $0) }
        )

        try BackupEntityImporter.importStudentMeetings(
            payload.studentMeetings,
            into: viewContext,
            existingCheck: { try index.exists(CDStudentMeeting.self, id: $0) }
        )

        try BackupEntityImporter.importProposedSolutions(
            payload.proposedSolutions,
            into: viewContext,
            existingCheck: { try index.exists(CDProposedSolutionEntity.self, id: $0) },
            topicCheck: { try index.related(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importCommunityAttachments(
            payload.communityAttachments,
            into: viewContext,
            existingCheck: { try index.exists(CDCommunityAttachmentEntity.self, id: $0) },
            topicCheck: { try index.related(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importAttendanceRecords(
            payload.attendance,
            into: viewContext,
            existingCheck: { try index.exists(CDAttendanceRecord.self, id: $0) }
        )

        try BackupEntityImporter.importWorkCompletionRecords(
            payload.workCompletions,
            into: viewContext,
            existingCheck: { try index.exists(CDWorkCompletionRecord.self, id: $0) }
        )
    }

    private func importProjectEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        try BackupEntityImporter.importProjects(
            payload.projects,
            into: viewContext,
            existingCheck: { try index.exists(CDProject.self, id: $0) }
        )

        try BackupEntityImporter.importProjectRoles(
            payload.projectRoles,
            into: viewContext,
            existingCheck: { try index.exists(CDProjectRole.self, id: $0) }
        )

        // Import of CDProjectTemplateWeek, CDProjectAssignmentTemplate, and
        // CDProjectWeekRoleAssignment skipped — entities deprecated.

        try BackupEntityImporter.importProjectSessions(
            payload.projectSessions,
            into: viewContext,
            existingCheck: { try index.exists(CDProjectSession.self, id: $0) }
        )
    }

    private func importWorkTrackingEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        // CDWorkModel must be imported first — child entities reference it
        if let workModels = payload.workModels {
            try BackupEntityImporter.importWorkModels(
                workModels,
                into: viewContext,
                existingCheck: { try index.exists(CDWorkModel.self, id: $0) }
            )
        }

        if let workCheckIns = payload.workCheckIns {
            try BackupEntityImporter.importWorkCheckIns(
                workCheckIns,
                into: viewContext,
                existingCheck: { try index.exists(CDWorkCheckIn.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let workSteps = payload.workSteps {
            try BackupEntityImporter.importWorkSteps(
                workSteps,
                into: viewContext,
                existingCheck: { try index.exists(CDWorkStep.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let workParticipants = payload.workParticipants {
            try BackupEntityImporter.importWorkParticipants(
                workParticipants,
                into: viewContext,
                existingCheck: { try index.exists(CDWorkParticipantEntity.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let practiceSessions = payload.practiceSessions {
            try BackupEntityImporter.importPracticeSessions(
                practiceSessions,
                into: viewContext,
                existingCheck: { try index.exists(CDPracticeSession.self, id: $0) }
            )
        }
    }

    private func importLessonExtras(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let lessonAttachments = payload.lessonAttachments {
            try BackupEntityImporter.importLessonAttachments(
                lessonAttachments,
                into: viewContext,
                existingCheck: { try index.exists(CDLessonAttachment.self, id: $0) },
                lessonCheck: { try index.related(CDLesson.self, id: $0) }
            )
        }

        if let lessonPresentations = payload.lessonPresentations {
            try BackupEntityImporter.importLessonPresentations(
                lessonPresentations,
                into: viewContext,
                existingCheck: { try index.exists(CDLessonPresentation.self, id: $0) }
            )
        }

        if let recallChecks = payload.recallChecks {
            try BackupEntityImporter.importRecallChecks(
                recallChecks,
                into: viewContext,
                existingCheck: { try index.exists(CDLessonRecallCheck.self, id: $0) }
            )
        }

        if let sampleWorks = payload.sampleWorks {
            try BackupEntityImporter.importSampleWorks(
                sampleWorks,
                into: viewContext,
                existingCheck: { try index.exists(CDSampleWork.self, id: $0) },
                lessonCheck: { try index.related(CDLesson.self, id: $0) }
            )
        }

        if let sampleWorkSteps = payload.sampleWorkSteps {
            try BackupEntityImporter.importSampleWorkSteps(
                sampleWorkSteps,
                into: viewContext,
                existingCheck: { try index.exists(CDSampleWorkStep.self, id: $0) },
                sampleWorkCheck: { try index.related(CDSampleWork.self, id: $0) }
            )
        }
    }

    private func importTemplateEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let noteTemplates = payload.noteTemplates {
            try BackupEntityImporter.importNoteTemplates(
                noteTemplates,
                into: viewContext,
                existingCheck: { try index.exists(CDNoteTemplate.self, id: $0) }
            )
        }

        if let meetingTemplates = payload.meetingTemplates {
            try BackupEntityImporter.importMeetingTemplates(
                meetingTemplates,
                into: viewContext,
                existingCheck: { try index.exists(CDMeetingTemplate.self, id: $0) }
            )
        }

        if let reminders = payload.reminders {
            try BackupEntityImporter.importReminders(
                reminders,
                into: viewContext,
                existingCheck: { try index.exists(CDReminder.self, id: $0) }
            )
        }

        if let calendarEvents = payload.calendarEvents {
            try BackupEntityImporter.importCalendarEvents(
                calendarEvents,
                into: viewContext,
                existingCheck: { try index.exists(CDCalendarEvent.self, id: $0) }
            )
        }
    }

    private func importTrackEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let tracks = payload.tracks {
            try BackupEntityImporter.importTracks(
                tracks,
                into: viewContext,
                existingCheck: { try index.exists(CDTrackEntity.self, id: $0) }
            )
        }

        if let trackSteps = payload.trackSteps {
            try BackupEntityImporter.importTrackSteps(
                trackSteps,
                into: viewContext,
                existingCheck: { try index.exists(CDTrackStepEntity.self, id: $0) },
                trackCheck: { try index.related(CDTrackEntity.self, id: $0) }
            )
        }

        if let enrollments = payload.studentTrackEnrollments {
            try BackupEntityImporter.importStudentTrackEnrollments(
                enrollments,
                into: viewContext,
                existingCheck: { try index.exists(CDStudentTrackEnrollmentEntity.self, id: $0) },
                studentCheck: { try index.related(CDStudent.self, id: $0) },
                trackCheck: { try index.related(CDTrackEntity.self, id: $0) }
            )
        }

        if let sequenceTracks = payload.sequenceTracks {
            try BackupEntityImporter.importSequenceTracks(
                sequenceTracks,
                into: viewContext,
                existingCheck: { try index.exists(CDSequenceTrack.self, id: $0) }
            )
        }
    }

    private func importDocumentEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let documents = payload.documents {
            try BackupEntityImporter.importDocuments(
                documents,
                into: viewContext,
                existingCheck: { try index.exists(CDDocument.self, id: $0) }
            )
        }

        if let supplies = payload.supplies {
            try BackupEntityImporter.importSupplies(
                supplies,
                into: viewContext,
                existingCheck: { try index.exists(CDSupply.self, id: $0) }
            )
        }

        if let procedures = payload.procedures {
            try BackupEntityImporter.importProcedures(
                procedures,
                into: viewContext,
                existingCheck: { try index.exists(CDProcedure.self, id: $0) }
            )
        }
    }

    private func importScheduleEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let schedules = payload.schedules {
            try BackupEntityImporter.importSchedules(
                schedules,
                into: viewContext,
                existingCheck: { try index.exists(CDSchedule.self, id: $0) }
            )
        }

        if let scheduleSlots = payload.scheduleSlots {
            try BackupEntityImporter.importScheduleSlots(
                scheduleSlots,
                into: viewContext,
                existingCheck: { try index.exists(CDScheduleSlot.self, id: $0) },
                scheduleCheck: { try index.related(CDSchedule.self, id: $0) }
            )
        }
    }

    private func importIssueEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let issues = payload.issues {
            try BackupEntityImporter.importIssues(
                issues,
                into: viewContext,
                existingCheck: { try index.exists(CDIssue.self, id: $0) }
            )
        }

        if let issueActions = payload.issueActions {
            try BackupEntityImporter.importIssueActions(
                issueActions,
                into: viewContext,
                existingCheck: { try index.exists(CDIssueAction.self, id: $0) },
                issueCheck: { try index.related(CDIssue.self, id: $0) }
            )
        }
    }

    private func importSnapshotAndTodoEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let snapshots = payload.developmentSnapshots {
            try BackupEntityImporter.importDevelopmentSnapshots(
                snapshots,
                into: viewContext,
                existingCheck: { try index.exists(CDDevelopmentSnapshotEntity.self, id: $0) }
            )
        }

        if let todoItems = payload.todoItems {
            try BackupEntityImporter.importTodoItems(
                todoItems,
                into: viewContext,
                existingCheck: { try index.exists(CDTodoItem.self, id: $0) }
            )
        }

        if let todoSubtasks = payload.todoSubtasks {
            try BackupEntityImporter.importTodoSubtasks(
                todoSubtasks,
                into: viewContext,
                existingCheck: { try index.exists(CDTodoSubtask.self, id: $0) },
                todoCheck: { try index.related(CDTodoItem.self, id: $0) }
            )
        }

        if let todoTemplates = payload.todoTemplates {
            try BackupEntityImporter.importTodoTemplates(
                todoTemplates,
                into: viewContext,
                existingCheck: { try index.exists(CDTodoTemplate.self, id: $0) }
            )
        }

        if let agendaOrders = payload.todayAgendaOrders {
            try BackupEntityImporter.importTodayAgendaOrders(
                agendaOrders,
                into: viewContext,
                existingCheck: { try index.exists(CDTodayAgendaOrder.self, id: $0) }
            )
        }
    }

    private func importAdditionalEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let recommendations = payload.planningRecommendations {
            try BackupEntityImporter.importPlanningRecommendations(
                recommendations,
                into: viewContext,
                existingCheck: { try index.exists(CDPlanningRecommendation.self, id: $0) }
            )
        }

        if let resources = payload.resources {
            try BackupEntityImporter.importResources(
                resources,
                into: viewContext,
                existingCheck: { try index.exists(CDResource.self, id: $0) }
            )
        }

        if let noteStudentLinks = payload.noteStudentLinks {
            try BackupEntityImporter.importNoteStudentLinks(
                noteStudentLinks,
                into: viewContext,
                existingCheck: { try index.exists(CDNoteStudentLink.self, id: $0) },
                noteCheck: { try index.related(CDNote.self, id: $0) }
            )
        }
    }

    private func importV12Entities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let goingOuts = payload.goingOuts {
            try BackupEntityImporter.importGoingOuts(
                goingOuts,
                into: viewContext,
                existingCheck: { try index.exists(CDGoingOut.self, id: $0) }
            )
        }

        if let goingOutItems = payload.goingOutChecklistItems {
            try BackupEntityImporter.importGoingOutChecklistItems(
                goingOutItems,
                into: viewContext,
                existingCheck: { try index.exists(CDGoingOutChecklistItem.self, id: $0) },
                goingOutCheck: { try index.related(CDGoingOut.self, id: $0) }
            )
        }

        if let classroomJobs = payload.classroomJobs {
            try BackupEntityImporter.importClassroomJobs(
                classroomJobs,
                into: viewContext,
                existingCheck: { try index.exists(CDClassroomJob.self, id: $0) }
            )
        }

        if let jobAssignments = payload.jobAssignments {
            try BackupEntityImporter.importJobAssignments(
                jobAssignments,
                into: viewContext,
                existingCheck: { try index.exists(CDJobAssignment.self, id: $0) },
                jobCheck: { try index.related(CDClassroomJob.self, id: $0) }
            )
        }

        if let calendarNotes = payload.calendarNotes {
            try BackupEntityImporter.importCalendarNotes(
                calendarNotes,
                into: viewContext,
                existingCheck: { try index.exists(CDCalendarNote.self, id: $0) }
            )
        }

        if let scheduledMeetings = payload.scheduledMeetings {
            try BackupEntityImporter.importScheduledMeetings(
                scheduledMeetings,
                into: viewContext,
                existingCheck: { try index.exists(CDScheduledMeeting.self, id: $0) }
            )
        }

        // v13+ entities
        if let memberships = payload.classroomMemberships {
            try BackupEntityImporter.importClassroomMemberships(
                memberships,
                into: viewContext,
                existingCheck: { try index.exists(CDClassroomMembership.self, id: $0) }
            )
        }

        // v14+ entities
        if let meetingWorkReviews = payload.meetingWorkReviews {
            BackupEntityImporter.importMeetingWorkReviews(
                meetingWorkReviews,
                into: viewContext,
                existingCheck: { try index.exists(CDMeetingWorkReview.self, id: $0) }
            )
        }

        if let studentFocusItems = payload.studentFocusItems {
            BackupEntityImporter.importStudentFocusItems(
                studentFocusItems,
                into: viewContext,
                existingCheck: { try index.exists(CDStudentFocusItem.self, id: $0) }
            )
        }
    }

    /// v18+ entities: Stories, Book Club, Year Plan, Lesson Sequence Settings, Day Pads.
    /// Book Club is imported packet -> session -> meeting so meetings can re-wire
    /// their `session` relationship against sessions already in the context.
    private func importV18Entities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let dayPads = payload.dayPads {
            try BackupEntityImporter.importDayPads(
                dayPads,
                into: viewContext,
                existingCheck: { try index.exists(CDDayPad.self, id: $0) }
            )
        }

        if let yearPlanEntries = payload.yearPlanEntries {
            try BackupEntityImporter.importYearPlanEntries(
                yearPlanEntries,
                into: viewContext,
                existingCheck: { try index.exists(CDYearPlanEntry.self, id: $0) }
            )
        }

        if let sequenceSettings = payload.lessonSequenceSettings {
            try BackupEntityImporter.importLessonSequenceSettings(
                sequenceSettings,
                into: viewContext,
                existingCheck: { try index.exists(CDLessonSequenceSettings.self, id: $0) }
            )
        }

        if let stories = payload.stories {
            try BackupEntityImporter.importStories(
                stories,
                into: viewContext,
                existingCheck: { try index.exists(CDStory.self, id: $0) }
            )
        }

        if let packets = payload.bookClubPackets {
            try BackupEntityImporter.importBookClubPackets(
                packets,
                into: viewContext,
                existingCheck: { try index.exists(CDBookClubPacket.self, id: $0) }
            )
        }

        if let sessions = payload.bookClubSessions {
            try BackupEntityImporter.importBookClubSessions(
                sessions,
                into: viewContext,
                existingCheck: { try index.exists(CDBookClubSession.self, id: $0) }
            )
        }

        if let meetings = payload.bookClubMeetings {
            try BackupEntityImporter.importBookClubMeetings(
                meetings,
                into: viewContext,
                existingCheck: { try index.exists(CDBookClubMeeting.self, id: $0) },
                sessionCheck: { try index.related(CDBookClubSession.self, id: $0) }
            )
        }
    }

    private func repairDenormalizedFields(viewContext: NSManagedObjectContext) throws {
        let assignmentsForRepair = try viewContext.fetch(
            NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        )
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
