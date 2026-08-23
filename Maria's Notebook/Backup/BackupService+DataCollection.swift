import Foundation
import CoreData
import SwiftUI
import CryptoKit
import Compression
import OSLog

// MARK: - Data Collection & Export Pipeline

extension BackupService {

    private static let logger = Logger.backup

    /// Collects every backup-eligible Core Data entity into a `BackupPayload`.
    /// Exposed for reuse by the archive implementation, which serializes the
    /// payload to AEA-framed NDJSON instead of the legacy JSON envelope.
    public func collectPayload(
        viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback = { _, _ in }
    ) -> BackupPayload {
        var payload = BackupPayload(
            items: [], students: [], lessons: [],
            lessonAssignments: [],
            notes: [], nonSchoolDays: [], schoolDayOverrides: [],
            studentMeetings: [], communityTopics: [],
            proposedSolutions: [], communityAttachments: [],
            attendance: [], workCompletions: [],
            projects: [], projectAssignmentTemplates: [],
            projectSessions: [], projectRoles: [],
            projectTemplateWeeks: [], projectWeekRoleAssignments: [],
            preferences: buildPreferencesDTO()
        )

        collectCoreEntityDTOs(into: &payload, using: viewContext, progress: progress)
        collectRelationAndProjectDTOs(into: &payload, using: viewContext, progress: progress)
        collectWorkTrackingDTOs(into: &payload, using: viewContext, progress: progress)
        collectTemplateAndTrackDTOs(into: &payload, using: viewContext, progress: progress)
        collectOrganizationDTOs(into: &payload, using: viewContext, progress: progress)
        collectV18DTOs(into: &payload, using: viewContext, progress: progress)
        collectV20DTOs(into: &payload, using: viewContext, progress: progress)

        return payload
    }

    // MARK: - DTO Collection Helpers

    private func collectCoreEntityDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students\u{2026}")
        payload.students = fetchAndTransformInBatches(
            CDStudent.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons\u{2026}")
        payload.lessons = fetchAndTransformInBatches(
            CDLesson.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.15), "Collecting lesson assignments\u{2026}")
        payload.lessonAssignments = fetchAndTransformInBatches(
            CDLessonAssignment.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.24), "Collecting notes\u{2026}")
        payload.notes = fetchAndTransformInBatches(
            CDNote.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.27), "Collecting calendar data\u{2026}")
        payload.nonSchoolDays = fetchAndTransformInBatches(
            CDNonSchoolDay.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.schoolDayOverrides = fetchAndTransformInBatches(
            CDSchoolDayOverride.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
    }

    private func collectRelationAndProjectDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings\u{2026}")
        payload.studentMeetings = fetchAndTransformInBatches(
            CDStudentMeeting.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data\u{2026}")
        payload.communityTopics = fetchAndTransformInBatches(
            CDCommunityTopicEntity.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.proposedSolutions = fetchAndTransformInBatches(
            CDProposedSolutionEntity.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.communityAttachments = fetchAndTransformInBatches(
            CDCommunityAttachmentEntity.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.36),
            "Collecting attendance and work completions\u{2026}"
        )
        payload.attendance = fetchAndTransformInBatches(
            CDAttendanceRecord.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.workCompletions = fetchAndTransformInBatches(
            CDWorkCompletionRecord.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.39), "Collecting projects\u{2026}")
        payload.projects = fetchAndTransformInBatches(
            CDProject.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectAssignmentTemplates = [] // Deprecated
        payload.projectSessions = fetchAndTransformInBatches(
            CDProjectSession.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectRoles = fetchAndTransformInBatches(
            CDProjectRole.self, using: viewContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectTemplateWeeks = [] // Deprecated
        payload.projectWeekRoleAssignments = [] // Deprecated
    }

    private func collectWorkTrackingDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.42), "Collecting work tracking\u{2026}")
        payload.workModels = fetchAndTransformInBatches(
            CDWorkModel.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workCheckIns = fetchAndTransformInBatches(
            CDWorkCheckIn.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workSteps = fetchAndTransformInBatches(
            CDWorkStep.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workParticipants = fetchAndTransformInBatches(
            CDWorkParticipantEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.practiceSessions = fetchAndTransformInBatches(
            CDPracticeSession.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.50), "Collecting lesson extras\u{2026}")
        payload.lessonAttachments = fetchAndTransformInBatches(
            CDLessonAttachment.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.lessonPresentations = fetchAndTransformInBatches(
            CDLessonPresentation.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.recallChecks = fetchAndTransformInBatches(
            CDLessonRecallCheck.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.sampleWorks = fetchAndTransformInBatches(
            CDSampleWork.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.sampleWorkSteps = fetchAndTransformInBatches(
            CDSampleWorkStep.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    private func collectTemplateAndTrackDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.55), "Collecting templates & tracks\u{2026}")
        payload.noteTemplates = fetchAndTransformInBatches(
            CDNoteTemplate.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.meetingTemplates = fetchAndTransformInBatches(
            CDMeetingTemplate.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.reminders = fetchAndTransformInBatches(
            CDReminder.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.calendarEvents = fetchAndTransformInBatches(
            CDCalendarEvent.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.tracks = fetchAndTransformInBatches(
            CDTrackEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.trackSteps = fetchAndTransformInBatches(
            CDTrackStepEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.studentTrackEnrollments = fetchAndTransformInBatches(
            CDStudentTrackEnrollmentEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.sequenceTracks = fetchAndTransformInBatches(
            CDSequenceTrack.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    private func collectOrganizationDTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.65),
            "Collecting supplies, schedules & issues\u{2026}"
        )
        payload.documents = fetchAndTransformInBatches(
            CDDocument.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.supplies = fetchAndTransformInBatches(
            CDSupply.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.procedures = fetchAndTransformInBatches(
            CDProcedure.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.schedules = fetchAndTransformInBatches(
            CDSchedule.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.scheduleSlots = fetchAndTransformInBatches(
            CDScheduleSlot.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.issues = fetchAndTransformInBatches(
            CDIssue.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.issueActions = fetchAndTransformInBatches(
            CDIssueAction.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.75), "Collecting snapshots & todos\u{2026}")
        payload.developmentSnapshots = fetchAndTransformInBatches(
            CDDevelopmentSnapshotEntity.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoItems = fetchAndTransformInBatches(
            CDTodoItem.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoSubtasks = fetchAndTransformInBatches(
            CDTodoSubtask.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoTemplates = fetchAndTransformInBatches(
            CDTodoTemplate.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todayAgendaOrders = fetchAndTransformInBatches(
            CDTodayAgendaOrder.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.80),
            "Collecting recommendations & resources\u{2026}"
        )
        payload.planningRecommendations = fetchAndTransformInBatches(
            CDPlanningRecommendation.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.resources = fetchAndTransformInBatches(
            CDResource.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.noteStudentLinks = fetchAndTransformInBatches(
            CDNoteStudentLink.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.85),
            "Collecting going-outs, jobs & transitions\u{2026}"
        )
        payload.goingOuts = fetchAndTransformInBatches(
            CDGoingOut.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.goingOutChecklistItems = fetchAndTransformInBatches(
            CDGoingOutChecklistItem.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.classroomJobs = fetchAndTransformInBatches(
            CDClassroomJob.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.jobAssignments = fetchAndTransformInBatches(
            CDJobAssignment.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.90),
            "Collecting calendar notes & meetings\u{2026}"
        )
        payload.calendarNotes = fetchAndTransformInBatches(
            CDCalendarNote.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.scheduledMeetings = fetchAndTransformInBatches(
            CDScheduledMeeting.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.93),
            "Collecting classroom memberships\u{2026}"
        )
        payload.classroomMemberships = fetchAndTransformInBatches(
            CDClassroomMembership.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.95),
            "Collecting meeting work reviews & focus items\u{2026}"
        )
        payload.meetingWorkReviews = fetchAndTransformInBatches(
            CDMeetingWorkReview.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.studentFocusItems = fetchAndTransformInBatches(
            CDStudentFocusItem.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    /// Collects the format v18 entity types: Stories, Book Club, Year Plan,
    /// Lesson Sequence Settings, and Day Pads.
    private func collectV18DTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.97),
            "Collecting stories, book club & year plan\u{2026}"
        )
        payload.dayPads = fetchAndTransformInBatches(
            CDDayPad.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.yearPlanEntries = fetchAndTransformInBatches(
            CDYearPlanEntry.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.lessonSequenceSettings = fetchAndTransformInBatches(
            CDLessonSequenceSettings.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.stories = fetchAndTransformInBatches(
            CDStory.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.bookClubPackets = fetchAndTransformInBatches(
            CDBookClubPacket.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.bookClubSessions = fetchAndTransformInBatches(
            CDBookClubSession.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.bookClubMeetings = fetchAndTransformInBatches(
            CDBookClubMeeting.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    /// Collects the format v20 entity types: Guardians and Parent Communications.
    private func collectV20DTOs(
        into payload: inout BackupPayload,
        using viewContext: NSManagedObjectContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.98),
            "Collecting guardians & parent communications\u{2026}"
        )
        payload.guardians = fetchAndTransformInBatches(
            CDGuardian.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
        payload.parentCommunications = fetchAndTransformInBatches(
            CDParentCommunication.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }

    // MARK: - Batched Fetch Utilities

    /// Modern fetch-and-transform pattern that converts entities to DTOs in batches.
    /// This reduces peak memory usage by not holding both models and DTOs simultaneously.
    func fetchAndTransformInBatches<T: NSManagedObject, DTO>(
        _ type: T.Type,
        using context: NSManagedObjectContext,
        batchSize: Int = 1000,
        transform: ([T]) -> [DTO]
    ) -> [DTO] {
        // Guard: ensure the entity is registered in the context's model before fetching.
        // Without this, T.fetchRequest() throws an unrecoverable ObjC NSException
        // when the persistent stores haven't fully loaded (e.g. during pre-migration backup).
        let typeName = String(describing: T.self)
        guard let coordinator = context.persistentStoreCoordinator else {
            Self.logger.warning(
                "Skipping fetch for \(typeName, privacy: .public) — no persistent store coordinator"
            )
            return []
        }

        // Resolve the entity NAME from THIS context's model rather than the
        // `T.entity()` class method (which also serves as the "entity exists" guard).
        // When more than one NSManagedObjectModel is loaded in the process (e.g. a
        // test host app's stack alongside an in-memory test stack), `T.entity().name`
        // can return nil — and a fetch keyed on the class name ("CDStudent") instead
        // of the entity name ("Student") raises an uncaught NSException. The
        // per-coordinator model lookup is unambiguous.
        guard let entityName = coordinator.managedObjectModel.entitiesByName.values
            .first(where: { $0.managedObjectClassName == NSStringFromClass(T.self) })?.name else {
            Self.logger.info(
                "Skipping fetch for \(typeName, privacy: .public) — no entity in model"
            )
            return []
        }

        var allDTOs: [DTO] = []
        var offset = 0

        while true {
            // Fetch, transform, and release in one autoreleasepool
            let dtos: [DTO]? = autoreleasepool {
                let descriptor = NSFetchRequest<T>(entityName: entityName)
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize

                let batch: [T]
                do {
                    batch = try context.fetch(descriptor)
                } catch {
                    let typeName = String(describing: T.self)
                    let desc = error.localizedDescription
                    Self.logger.warning(
                        "Batch fetch failed \(typeName, privacy: .public): \(desc, privacy: .public)"
                    )
                    return nil
                }

                guard !batch.isEmpty else {
                    return nil
                }

                // Transform to DTOs immediately while models are in scope
                let transformed = transform(batch)

                // Batch objects are released when autoreleasepool exits
                return transformed
            }

            guard let fetchedDTOs = dtos, !fetchedDTOs.isEmpty else { break }
            allDTOs.append(contentsOf: fetchedDTOs)

            if fetchedDTOs.count < batchSize { break }
            offset += batchSize
        }

        return allDTOs
    }
}
