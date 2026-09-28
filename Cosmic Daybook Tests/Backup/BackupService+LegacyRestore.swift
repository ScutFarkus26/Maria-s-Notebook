// swiftlint:disable file_length
import Foundation
import CoreData
import SwiftUI
import OSLog
@testable import CosmicDaybook

// The restore as it stood before it imported one entity type at a time
// (2026-09-27), copied verbatim from 3035fa87's `BackupService+Restoration.swift`,
// `BackupServiceHelpers.swift` (the payload deduplicator),
// `BackupEntityImporter+Misc.swift` (the note relink over whole Note rows) and
// `BackupImporter.swift` (`decodeArchive`, which read every entry before
// decoding any, and `importDecoded`). Only the entry points are renamed
// (`legacyDecodeArchive`, `legacyImportPayload`, `legacyImportDecoded`,
// `legacyRelinkNoteRelationships`, `LegacyBackupPayloadDeduplicator`),
// `CloudExportWaitResult` is the app's, and the SwiftLint findings the old
// code carried are silenced where they fall. The restore equivalence and
// peak-memory tests compare the new restore against it, so do not "fix" or
// modernise this code: its only job is to be the old code.

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

// MARK: - Restore Preview & Import

extension BackupService {
    /// Post-decode import path. Shared by:
    ///   - `BackupCoordinator` for archive imports (which reconstructs
    ///     a `BackupPayload` from archive entries then calls this)
    /// Centralizing this method means deleteAll, the entity-import dispatch,
    /// the denormalized-field repair, and the CloudKit-sync wait all share one
    /// code path across format versions.
    func legacyImportPayload( // swiftlint:disable:this function_body_length function_parameter_count
        payload loadedPayload: BackupPayload,
        envelope: BackupEnvelope,
        viewContext: NSManagedObjectContext,
        mode: RestoreMode,
        appRouter: AppRouter,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {

        var payload = loadedPayload
        progress(RestoreProgress.deduplication, "Deduplicating records\u{2026}")
        payload = LegacyBackupPayloadDeduplicator.deduplicate(payload)

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
        importV20Entities(from: payload, into: viewContext, index: index)
        importV21Entities(from: payload, into: viewContext, index: index)
        importV27Entities(from: payload, into: viewContext, index: index)

        // Notes import early, but many of their relationship targets (work,
        // check-ins, meetings, etc.) import in later phases — relink them now
        // that every target type is in the store.
        try BackupEntityImporter.legacyRelinkNoteRelationships(payload.notes, index: index)

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
        AlbumLibrary.shared.reloadAfterRestore()
        appRouter.signalAppDataDidRestore()

        // After save, the in-memory model is correct but CloudKit-mirrored stores still need
        // to upload the new records. Block briefly so users see a definitive "synced" message
        // when possible; on timeout, surface that sync is continuing in the background.
        progress(RestoreProgress.cloudSync, "Syncing to iCloud\u{2026}")
        let cloudResult = await cloudExportWait.value

        var warnings: [String] = []
        if let albumWarning = albumReattachWarning(for: payload) {
            warnings.append(albumWarning)
        }
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
            fileName: envelope.fileName,
            formatVersion: envelope.formatVersion,
            encryptUsed: envelope.encrypted,
            createdAt: envelope.createdAt,
            entityCounts: envelope.entityCounts,
            warnings: warnings
        )
    }

    // MARK: - Album Reattachment

    /// Album bookmarks, notes, highlights, and ink key on the album PDF's
    /// filename. They restore intact, but on a device with no album folder
    /// registered they have nothing to attach to until the guide adds one —
    /// say so, rather than letting them look lost.
    private func albumReattachWarning(for payload: BackupPayload) -> String? {
        var albumIDs = Set<String>()
        albumIDs.formUnion(payload.albumBookmarks?.compactMap { $0.string("albumID") } ?? [])
        albumIDs.formUnion(payload.albumPageNotes?.compactMap { $0.string("albumID") } ?? [])
        payload.albumHighlights?.forEach { albumIDs.insert($0.albumID) }
        payload.albumPageInk?.forEach { albumIDs.insert($0.albumID) }
        albumIDs.formUnion(payload.albumReadingPositions?.compactMap { $0.string("albumID") } ?? [])
        guard !albumIDs.isEmpty, !AlbumLibrary.hasResolvableFolderBookmark() else { return nil }
        let noun = albumIDs.count == 1 ? "album" : "albums"
        return "This backup includes bookmarks, notes, highlights, or drawings for "
            + "\(albumIDs.count) \(noun). Open Albums and add your album folder to reattach them."
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
            existing: { try index.existing(CDStudent.self, id: $0) }
        )

        try BackupEntityImporter.importLessons(
            payload.lessons,
            into: viewContext,
            existing: { try index.existing(CDLesson.self, id: $0) }
        )

        try BackupEntityImporter.importCommunityTopics(
            payload.communityTopics,
            into: viewContext,
            existing: { try index.existing(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importLessonAssignments(
            payload.lessonAssignments,
            into: viewContext,
            existing: { try index.existing(CDLessonAssignment.self, id: $0) },
            lessonCheck: { try index.related(CDLesson.self, id: $0) }
        )

        try BackupEntityImporter.importNotes(
            payload.notes,
            into: viewContext,
            existing: { try index.existing(CDNote.self, id: $0) }
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
            existing: { try index.existing(CDNonSchoolDay.self, id: $0) }
        )

        try BackupEntityImporter.importSchoolDayOverrides(
            payload.schoolDayOverrides,
            into: viewContext,
            existing: { try index.existing(CDSchoolDayOverride.self, id: $0) }
        )

        try BackupEntityImporter.importStudentMeetings(
            payload.studentMeetings,
            into: viewContext,
            existing: { try index.existing(CDStudentMeeting.self, id: $0) }
        )

        BackupEntityImporter.importRows(
            payload.proposedSolutions, as: CDProposedSolutionEntity.self, into: viewContext,
            existing: { try index.existing(CDProposedSolutionEntity.self, id: $0) },
            parents: ["topic": { try index.related(CDCommunityTopicEntity.self, id: $0) }]
        )

        try BackupEntityImporter.importCommunityAttachments(
            payload.communityAttachments,
            into: viewContext,
            existing: { try index.existing(CDCommunityAttachment.self, id: $0) },
            topicCheck: { try index.related(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importAttendanceRecords(
            payload.attendance,
            into: viewContext,
            existing: { try index.existing(CDAttendanceRecord.self, id: $0) }
        )

        try BackupEntityImporter.importWorkCompletionRecords(
            payload.workCompletions,
            into: viewContext,
            existing: { try index.existing(CDWorkCompletionRecord.self, id: $0) }
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
            existing: { try index.existing(CDProject.self, id: $0) }
        )

        try BackupEntityImporter.importProjectRoles(
            payload.projectRoles,
            into: viewContext,
            existing: { try index.existing(CDProjectRole.self, id: $0) }
        )

        // Import of CDProjectTemplateWeek, CDProjectAssignmentTemplate, and
        // CDProjectWeekRoleAssignment skipped — entities deprecated.

        try BackupEntityImporter.importProjectSessions(
            payload.projectSessions,
            into: viewContext,
            existing: { try index.existing(CDProjectSession.self, id: $0) }
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
                existing: { try index.existing(CDWorkModel.self, id: $0) }
            )
        }

        if let workCheckIns = payload.workCheckIns {
            try BackupEntityImporter.importWorkCheckIns(
                workCheckIns,
                into: viewContext,
                existing: { try index.existing(CDWorkCheckIn.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let workSteps = payload.workSteps {
            BackupEntityImporter.importRows(
                workSteps, as: CDWorkStep.self, into: viewContext,
                existing: { try index.existing(CDWorkStep.self, id: $0) },
                parents: ["work": { try index.related(CDWorkModel.self, id: $0) }]
            )
        }

        if let workParticipants = payload.workParticipants {
            try BackupEntityImporter.importWorkParticipants(
                workParticipants,
                into: viewContext,
                existing: { try index.existing(CDWorkParticipantEntity.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let practiceSessions = payload.practiceSessions {
            try BackupEntityImporter.importPracticeSessions(
                practiceSessions,
                into: viewContext,
                existing: { try index.existing(CDPracticeSession.self, id: $0) }
            )
        }
    }

    private func importLessonExtras(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let lessonAttachments = payload.lessonAttachments {
            BackupEntityImporter.importRows(
                lessonAttachments, as: CDLessonAttachment.self, into: viewContext,
                existing: { try index.existing(CDLessonAttachment.self, id: $0) },
                parents: ["lesson": { try index.related(CDLesson.self, id: $0) }]
            )
        }

        if let lessonPresentations = payload.lessonPresentations {
            try BackupEntityImporter.importLessonPresentations(
                lessonPresentations,
                into: viewContext,
                existing: { try index.existing(CDLessonPresentation.self, id: $0) }
            )
        }

        if let recallChecks = payload.recallChecks {
            BackupEntityImporter.importRows(
                recallChecks, as: CDLessonRecallCheck.self, into: viewContext,
                existing: { try index.existing(CDLessonRecallCheck.self, id: $0) }
            )
        }

        if let sampleWorks = payload.sampleWorks {
            try BackupEntityImporter.importSampleWorks(
                sampleWorks,
                into: viewContext,
                existing: { try index.existing(CDSampleWork.self, id: $0) },
                lessonCheck: { try index.related(CDLesson.self, id: $0) }
            )
        }

        if let sampleWorkSteps = payload.sampleWorkSteps {
            BackupEntityImporter.importRows(
                sampleWorkSteps, as: CDSampleWorkStep.self, into: viewContext,
                existing: { try index.existing(CDSampleWorkStep.self, id: $0) },
                parents: ["sampleWork": { try index.related(CDSampleWork.self, id: $0) }]
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
                existing: { try index.existing(CDNoteTemplate.self, id: $0) }
            )
        }

        if let meetingTemplates = payload.meetingTemplates {
            BackupEntityImporter.importRows(
                meetingTemplates, as: CDMeetingTemplate.self, into: viewContext,
                existing: { try index.existing(CDMeetingTemplate.self, id: $0) }
            )
        }

        if let reminders = payload.reminders {
            try BackupEntityImporter.importReminders(
                reminders,
                into: viewContext,
                existing: { try index.existing(CDReminder.self, id: $0) }
            )
        }

        if let calendarEvents = payload.calendarEvents {
            try BackupEntityImporter.importCalendarEvents(
                calendarEvents,
                into: viewContext,
                existing: { try index.existing(CDCalendarEvent.self, id: $0) }
            )
        }
    }

    private func importTrackEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let tracks = payload.tracks {
            BackupEntityImporter.importRows(
                tracks, as: CDTrackEntity.self, into: viewContext,
                existing: { try index.existing(CDTrackEntity.self, id: $0) }
            )
        }

        if let trackSteps = payload.trackSteps {
            BackupEntityImporter.importRows(
                trackSteps, as: CDTrackStep.self, into: viewContext,
                existing: { try index.existing(CDTrackStep.self, id: $0) },
                parents: ["track": { try index.related(CDTrackEntity.self, id: $0) }]
            )
        }

        if let enrollments = payload.studentTrackEnrollments {
            BackupEntityImporter.importRows(
                enrollments, as: CDStudentTrackEnrollmentEntity.self, into: viewContext,
                existing: { try index.existing(CDStudentTrackEnrollmentEntity.self, id: $0) },
                parents: [
                    "student": { try index.related(CDStudent.self, id: $0) },
                    "track": { try index.related(CDTrackEntity.self, id: $0) }
                ]
            )
        }

        if let sequenceTracks = payload.sequenceTracks {
            try BackupEntityImporter.importSequenceTracks(
                sequenceTracks,
                into: viewContext,
                existing: { try index.existing(CDSequenceTrack.self, id: $0) }
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
                existing: { try index.existing(CDDocument.self, id: $0) }
            )
        }

        if let supplies = payload.supplies {
            try BackupEntityImporter.importSupplies(
                supplies,
                into: viewContext,
                existing: { try index.existing(CDSupply.self, id: $0) }
            )
        }

        if let procedures = payload.procedures {
            try BackupEntityImporter.importProcedures(
                procedures,
                into: viewContext,
                existing: { try index.existing(CDProcedure.self, id: $0) }
            )
        }
    }

    private func importScheduleEntities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let schedules = payload.schedules {
            BackupEntityImporter.importRows(
                schedules, as: CDSchedule.self, into: viewContext,
                existing: { try index.existing(CDSchedule.self, id: $0) }
            )
        }

        if let scheduleSlots = payload.scheduleSlots {
            try BackupEntityImporter.importScheduleSlots(
                scheduleSlots,
                into: viewContext,
                existing: { try index.existing(CDScheduleSlot.self, id: $0) },
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
                existing: { try index.existing(CDIssue.self, id: $0) }
            )
        }

        if let issueActions = payload.issueActions {
            try BackupEntityImporter.importIssueActions(
                issueActions,
                into: viewContext,
                existing: { try index.existing(CDIssueAction.self, id: $0) },
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
                existing: { try index.existing(CDDevelopmentSnapshotEntity.self, id: $0) }
            )
        }

        if let todoItems = payload.todoItems {
            try BackupEntityImporter.importTodoItems(
                todoItems,
                into: viewContext,
                existing: { try index.existing(CDTodoItem.self, id: $0) }
            )
        }

        if let todoSubtasks = payload.todoSubtasks {
            BackupEntityImporter.importRows(
                todoSubtasks, as: CDTodoSubtask.self, into: viewContext,
                existing: { try index.existing(CDTodoSubtask.self, id: $0) },
                parents: ["todo": { try index.related(CDTodoItem.self, id: $0) }]
            )
        }

        if let todoTemplates = payload.todoTemplates {
            try BackupEntityImporter.importTodoTemplates(
                todoTemplates,
                into: viewContext,
                existing: { try index.existing(CDTodoTemplate.self, id: $0) }
            )
        }

        if let agendaOrders = payload.todayAgendaOrders {
            try BackupEntityImporter.importTodayAgendaOrders(
                agendaOrders,
                into: viewContext,
                existing: { try index.existing(CDTodayAgendaOrder.self, id: $0) }
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
                existing: { try index.existing(CDPlanningRecommendation.self, id: $0) }
            )
        }

        if let resources = payload.resources {
            try BackupEntityImporter.importResources(
                resources,
                into: viewContext,
                existing: { try index.existing(CDResource.self, id: $0) }
            )
        }

        if let noteStudentLinks = payload.noteStudentLinks {
            BackupEntityImporter.importRows(
                noteStudentLinks, as: CDNoteStudentLink.self, into: viewContext,
                existing: { try index.existing(CDNoteStudentLink.self, id: $0) },
                parents: ["note": { try index.related(CDNote.self, id: $0) }]
            )
        }
    }

    private func importV12Entities( // swiftlint:disable:this function_body_length
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) throws {
        if let goingOuts = payload.goingOuts {
            BackupEntityImporter.importRows(
                goingOuts, as: CDGoingOut.self, into: viewContext,
                existing: { try index.existing(CDGoingOut.self, id: $0) }
            )
        }

        if let goingOutItems = payload.goingOutChecklistItems {
            try BackupEntityImporter.importGoingOutChecklistItems(
                goingOutItems,
                into: viewContext,
                existing: { try index.existing(CDGoingOutChecklistItem.self, id: $0) },
                goingOutCheck: { try index.related(CDGoingOut.self, id: $0) }
            )
        }

        if let classroomJobs = payload.classroomJobs {
            BackupEntityImporter.importRows(
                classroomJobs, as: CDClassroomJob.self, into: viewContext,
                existing: { try index.existing(CDClassroomJob.self, id: $0) }
            )
        }

        if let jobAssignments = payload.jobAssignments {
            BackupEntityImporter.importRows(
                jobAssignments, as: CDJobAssignment.self, into: viewContext,
                existing: { try index.existing(CDJobAssignment.self, id: $0) },
                parents: ["job": { try index.related(CDClassroomJob.self, id: $0) }]
            )
        }

        if let calendarNotes = payload.calendarNotes {
            BackupEntityImporter.importRows(
                calendarNotes, as: CDCalendarNote.self, into: viewContext,
                existing: { try index.existing(CDCalendarNote.self, id: $0) }
            )
        }

        if let scheduledMeetings = payload.scheduledMeetings {
            try BackupEntityImporter.importScheduledMeetings(
                scheduledMeetings,
                into: viewContext,
                existing: { try index.existing(CDScheduledMeeting.self, id: $0) }
            )
        }

        // v13+ entities
        if let memberships = payload.classroomMemberships {
            BackupEntityImporter.importRows(
                memberships, as: CDClassroomMembership.self, into: viewContext,
                existing: { try index.existing(CDClassroomMembership.self, id: $0) }
            )
        }

        // v14+ entities
        if let meetingWorkReviews = payload.meetingWorkReviews {
            BackupEntityImporter.importRows(
                meetingWorkReviews, as: CDMeetingWorkReview.self, into: viewContext,
                existing: { try index.existing(CDMeetingWorkReview.self, id: $0) },
                parents: ["meeting": { viewContext.object(CDStudentMeeting.self, id: $0) }]
            )
        }

        if let studentFocusItems = payload.studentFocusItems {
            BackupEntityImporter.importRows(
                studentFocusItems, as: CDStudentFocusItem.self, into: viewContext,
                existing: { try index.existing(CDStudentFocusItem.self, id: $0) }
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
            BackupEntityImporter.importRows(
                dayPads, as: CDDayPad.self, into: viewContext,
                existing: { try index.existing(CDDayPad.self, id: $0) }
            )
        }

        if let yearPlanEntries = payload.yearPlanEntries {
            BackupEntityImporter.importRows(
                yearPlanEntries, as: CDYearPlanEntry.self, into: viewContext,
                existing: { try index.existing(CDYearPlanEntry.self, id: $0) }
            )
        }

        if let sequenceSettings = payload.lessonSequenceSettings {
            BackupEntityImporter.importRows(
                sequenceSettings, as: CDLessonSequenceSettings.self, into: viewContext,
                existing: { try index.existing(CDLessonSequenceSettings.self, id: $0) }
            )
        }

        if let stories = payload.stories {
            try BackupEntityImporter.importStories(
                stories,
                into: viewContext,
                existing: { try index.existing(CDStory.self, id: $0) }
            )
        }

        if let packets = payload.bookClubPackets {
            try BackupEntityImporter.importBookClubPackets(
                packets,
                into: viewContext,
                existing: { try index.existing(CDBookClubPacket.self, id: $0) }
            )
        }

        if let sessions = payload.bookClubSessions {
            BackupEntityImporter.importRows(
                sessions, as: CDBookClubSession.self, into: viewContext,
                existing: { try index.existing(CDBookClubSession.self, id: $0) }
            )
        }

        if let meetings = payload.bookClubMeetings {
            BackupEntityImporter.importRows(
                meetings, as: CDBookClubMeeting.self, into: viewContext,
                existing: { try index.existing(CDBookClubMeeting.self, id: $0) },
                parents: ["session": { try index.related(CDBookClubSession.self, id: $0) }]
            )
        }
    }

    /// v20+ entities: Guardians and Parent Communications.
    private func importV20Entities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) {
        if let guardians = payload.guardians {
            BackupEntityImporter.importRows(
                guardians, as: CDGuardian.self, into: viewContext,
                existing: { try index.existing(CDGuardian.self, id: $0) }
            )
        }

        if let parentCommunications = payload.parentCommunications {
            BackupEntityImporter.importRows(
                parentCommunications, as: CDParentCommunication.self, into: viewContext,
                existing: { try index.existing(CDParentCommunication.self, id: $0) }
            )
        }
    }

    /// v21+ entities: teaching-album annotations.
    private func importV21Entities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) {
        if let bookmarks = payload.albumBookmarks {
            BackupEntityImporter.importRows(
                bookmarks, as: CDAlbumBookmark.self, into: viewContext,
                existing: { try index.existing(CDAlbumBookmark.self, id: $0) }
            )
        }

        if let notes = payload.albumPageNotes {
            BackupEntityImporter.importRows(
                notes, as: CDAlbumPageNote.self, into: viewContext,
                existing: { try index.existing(CDAlbumPageNote.self, id: $0) }
            )
        }

        if let visits = payload.albumRecentVisits {
            BackupEntityImporter.importRows(
                visits, as: CDAlbumRecentVisit.self, into: viewContext,
                existing: { try index.existing(CDAlbumRecentVisit.self, id: $0) }
            )
        }

        if let positions = payload.albumReadingPositions {
            BackupEntityImporter.importRows(
                positions, as: CDAlbumReadingPosition.self, into: viewContext,
                existing: { try index.existing(CDAlbumReadingPosition.self, id: $0) }
            )
        }

        if let highlights = payload.albumHighlights {
            BackupEntityImporter.importAlbumHighlights(
                highlights,
                into: viewContext,
                existing: { try index.existing(CDAlbumHighlight.self, id: $0) }
            )
        }

        if let ink = payload.albumPageInk {
            BackupEntityImporter.importAlbumPageInk(
                ink,
                into: viewContext,
                existing: { try index.existing(CDAlbumPageInk.self, id: $0) }
            )
        }
    }

    /// v27+ entities: Orders.
    private func importV27Entities(
        from payload: BackupPayload,
        into viewContext: NSManagedObjectContext,
        index: BackupEntityIndex
    ) {
        if let orderItems = payload.orderItems {
            BackupEntityImporter.importRows(
                orderItems, as: CDOrderItem.self, into: viewContext,
                existing: { try index.existing(CDOrderItem.self, id: $0) }
            )
        }
        // v30: locked attendance days, kept in step with the live restore.
        if let locks = payload.attendanceDayLocks {
            BackupEntityImporter.importRows(
                locks, as: CDAttendanceDayLock.self, into: viewContext,
                existing: { try index.existing(CDAttendanceDayLock.self, id: $0) }
            )
        }
    }

    private func repairDenormalizedFields(viewContext: NSManagedObjectContext) throws {
        let assignmentsForRepair = try viewContext.fetch(
            CDFetchRequest(CDLessonAssignment.self)
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

/// Helper for deduplicating backup payloads
enum LegacyBackupPayloadDeduplicator {

    // Removes duplicate records from the backup payload, keeping the first occurrence of each ID.
    // This handles backups created from databases that had duplicate records due to CloudKit sync issues.
    // Every backed-up type is deduplicated through `BackupEntityTable`, so none can be missed
    // (ClassroomMembership once was, and every restore dropped it); the payload is copied, not
    // rebuilt, so no field can fall out either.
    static func deduplicate(_ payload: BackupPayload) -> BackupPayload {
        var result = payload
        for entity in BackupEntityTable.entities {
            entity.deduplicate(&result)
        }
        // The retired project types still decode from old backups.
        result.projectAssignmentTemplates = uniqueByID(payload.projectAssignmentTemplates) { $0.id }
        result.projectTemplateWeeks = uniqueByID(payload.projectTemplateWeeks) { $0.id }
        result.projectWeekRoleAssignments = uniqueByID(payload.projectWeekRoleAssignments) { $0.id }
        return result
    }

    private static func uniqueByID<T>(_ items: [T], id: (T) -> UUID) -> [T] {
        var seen = Set<UUID>()
        return items.filter { seen.insert(id($0)).inserted }
    }
}

extension BackupEntityImporter {
    /// Relinks a note's context relationships after all entities are imported.
    ///
    /// Notes import early, but most of their relationship targets (work,
    /// check-ins, meetings, issues, etc.) import in later phases — so they can't
    /// be resolved at note-import time. This runs as a final pass, once every
    /// target type is in the store, and wires them up by id.
    static func legacyRelinkNoteRelationships(_ dtos: [NoteDTO], index: BackupEntityIndex) throws { // swiftlint:disable:this cyclomatic_complexity line_length
        for dto in dtos {
            guard let note = try index.related(CDNote.self, id: dto.id) else { continue }
            if let id = dto.workID {
                note.work = try index.related(CDWorkModel.self, id: id)
            }
            if let id = dto.lessonAssignmentID {
                note.lessonAssignment = try index.related(CDLessonAssignment.self, id: id)
            }
            if let id = dto.attendanceRecordID {
                // A string FK, so it restores whether or not the record itself
                // made this backup — nothing to resolve through the index.
                note.attendanceRecordID = id.uuidString
            }
            if let id = dto.workCheckInID {
                note.workCheckIn = try index.related(CDWorkCheckIn.self, id: id)
            }
            if let id = dto.workCompletionRecordID {
                note.workCompletionRecord = try index.related(CDWorkCompletionRecord.self, id: id)
            }
            if let id = dto.studentMeetingID {
                note.studentMeeting = try index.related(CDStudentMeeting.self, id: id)
            }
            if let id = dto.projectSessionID {
                note.projectSession = try index.related(CDProjectSession.self, id: id)
            }
            if let id = dto.reminderID {
                note.reminder = try index.related(CDReminder.self, id: id)
            }
            if let id = dto.practiceSessionID {
                note.practiceSession = try index.related(CDPracticeSession.self, id: id)
            }
            if let id = dto.issueID {
                note.issue = try index.related(CDIssue.self, id: id)
            }
        }
    }
}

extension BackupImporter {
    /// Reads, decrypts, and JSON-decodes the archive into a typed payload.
    /// `@concurrent` so the whole decode pipeline runs off the main actor
    /// (a plain `nonisolated async` function runs on its caller's actor, and
    /// every caller is main-actor code); only the Core Data import that
    /// follows needs the main actor.
    @concurrent
    nonisolated static func legacyDecodeArchive(at url: URL) async throws -> DecodedArchive {
        BackupPipelineProbe.reach("decode")
        let decoded = try BackupReader.read(from: url)
        let (payload, warnings) = reconstructPayload(from: decoded)
        return DecodedArchive(
            manifest: decoded.manifest,
            payload: payload,
            warnings: warnings,
            encrypted: BackupArchive.isEncryptedArchive(at: url)
        )
    }

    /// Imports a decoded backup into the given Core Data context.
    /// Mode handling (merge/replace), deleteAll, save, CloudKit-sync-wait, and
    /// the operation summary are all owned by the underlying `importPayload`.
    /// Decode-time warnings are appended to the summary so partial decodes
    /// are visible in the UI, not just the log.
    static func legacyImportDecoded( // swiftlint:disable:this function_parameter_count
        _ archive: DecodedArchive,
        from fileURL: URL,
        into viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        appRouter: AppRouter,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        progress(0.35, "Importing\u{2026}")
        let service = BackupService()
        let summary = try await service.legacyImportPayload(
            payload: archive.payload,
            envelope: BackupEnvelope(
                formatVersion: archive.manifest.formatVersion,
                encrypted: archive.encrypted,
                createdAt: archive.manifest.createdAt,
                fileName: fileURL.lastPathComponent,
                entityCounts: archive.manifest.entityCounts
            ),
            viewContext: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
        return archive.warnings.isEmpty ? summary : summary.appending(warnings: archive.warnings)
    }
}
