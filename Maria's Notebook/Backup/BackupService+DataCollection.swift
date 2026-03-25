// swiftlint:disable file_length
import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import Compression
import OSLog

// MARK: - Data Collection & Export Pipeline

extension BackupService {

    private static let logger = Logger.backup

    func performExport(
        modelContext: ModelContext,
        to url: URL,
        password: String?,
        progress: @escaping ProgressCallback
    ) throws -> BackupOperationSummary {
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

        collectCoreEntityDTOs(into: &payload, using: modelContext, progress: progress)
        collectRelationAndProjectDTOs(into: &payload, using: modelContext, progress: progress)
        collectWorkTrackingDTOs(into: &payload, using: modelContext, progress: progress)
        collectTemplateAndTrackDTOs(into: &payload, using: modelContext, progress: progress)
        collectOrganizationDTOs(into: &payload, using: modelContext, progress: progress)

        return try encodeAndWriteExport(
            payload: payload, to: url, password: password, progress: progress
        )
    }

    // MARK: - DTO Collection Helpers

    private func collectCoreEntityDTOs(
        into payload: inout BackupPayload,
        using modelContext: ModelContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students\u{2026}")
        payload.students = fetchAndTransformInBatches(
            Student.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons\u{2026}")
        payload.lessons = fetchAndTransformInBatches(
            Lesson.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.15), "Collecting lesson assignments\u{2026}")
        payload.lessonAssignments = fetchAndTransformInBatches(
            LessonAssignment.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.24), "Collecting notes\u{2026}")
        payload.notes = fetchAndTransformInBatches(
            Note.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.27), "Collecting calendar data\u{2026}")
        payload.nonSchoolDays = fetchAndTransformInBatches(
            NonSchoolDay.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.schoolDayOverrides = fetchAndTransformInBatches(
            SchoolDayOverride.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
    }

    private func collectRelationAndProjectDTOs(
        into payload: inout BackupPayload,
        using modelContext: ModelContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings\u{2026}")
        payload.studentMeetings = fetchAndTransformInBatches(
            StudentMeeting.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data\u{2026}")
        payload.communityTopics = fetchAndTransformInBatches(
            CommunityTopic.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.proposedSolutions = fetchAndTransformInBatches(
            ProposedSolution.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.communityAttachments = fetchAndTransformInBatches(
            CommunityAttachment.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.36),
            "Collecting attendance and work completions\u{2026}"
        )
        payload.attendance = fetchAndTransformInBatches(
            AttendanceRecord.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.workCompletions = fetchAndTransformInBatches(
            WorkCompletionRecord.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.39), "Collecting projects\u{2026}")
        payload.projects = fetchAndTransformInBatches(
            Project.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectAssignmentTemplates = fetchAndTransformInBatches(
            ProjectAssignmentTemplate.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectSessions = fetchAndTransformInBatches(
            ProjectSession.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectRoles = fetchAndTransformInBatches(
            ProjectRole.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectTemplateWeeks = fetchAndTransformInBatches(
            ProjectTemplateWeek.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        payload.projectWeekRoleAssignments = fetchAndTransformInBatches(
            ProjectWeekRoleAssignment.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
    }

    private func collectWorkTrackingDTOs(
        into payload: inout BackupPayload,
        using modelContext: ModelContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.42), "Collecting work tracking\u{2026}")
        payload.workModels = fetchAndTransformInBatches(
            WorkModel.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workCheckIns = fetchAndTransformInBatches(
            WorkCheckIn.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workSteps = fetchAndTransformInBatches(
            WorkStep.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.workParticipants = fetchAndTransformInBatches(
            WorkParticipantEntity.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.practiceSessions = fetchAndTransformInBatches(
            PracticeSession.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.50), "Collecting lesson extras\u{2026}")
        payload.lessonAttachments = fetchAndTransformInBatches(
            LessonAttachment.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.lessonPresentations = fetchAndTransformInBatches(
            LessonPresentation.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.sampleWorks = fetchAndTransformInBatches(
            SampleWork.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.sampleWorkSteps = fetchAndTransformInBatches(
            SampleWorkStep.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
    }

    private func collectTemplateAndTrackDTOs(
        into payload: inout BackupPayload,
        using modelContext: ModelContext,
        progress: @escaping ProgressCallback
    ) {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.55), "Collecting templates & tracks\u{2026}")
        payload.noteTemplates = fetchAndTransformInBatches(
            NoteTemplate.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.meetingTemplates = fetchAndTransformInBatches(
            MeetingTemplate.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.reminders = fetchAndTransformInBatches(
            Reminder.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.calendarEvents = fetchAndTransformInBatches(
            CalendarEvent.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.tracks = fetchAndTransformInBatches(
            Track.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.trackSteps = fetchAndTransformInBatches(
            TrackStep.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.studentTrackEnrollments = fetchAndTransformInBatches(
            StudentTrackEnrollment.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.groupTracks = fetchAndTransformInBatches(
            GroupTrack.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
    }

    private func collectOrganizationDTOs(
        into payload: inout BackupPayload,
        using modelContext: ModelContext,
        progress: @escaping ProgressCallback
    ) {
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.65),
            "Collecting supplies, schedules & issues\u{2026}"
        )
        payload.documents = fetchAndTransformInBatches(
            Document.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.supplies = fetchAndTransformInBatches(
            Supply.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.supplyTransactions = fetchAndTransformInBatches(
            SupplyTransaction.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.procedures = fetchAndTransformInBatches(
            Procedure.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.schedules = fetchAndTransformInBatches(
            Schedule.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.scheduleSlots = fetchAndTransformInBatches(
            ScheduleSlot.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.issues = fetchAndTransformInBatches(
            Issue.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.issueActions = fetchAndTransformInBatches(
            IssueAction.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }

        progress(BackupProgress.progress(for: .collecting, subProgress: 0.75), "Collecting snapshots & todos\u{2026}")
        payload.developmentSnapshots = fetchAndTransformInBatches(
            DevelopmentSnapshot.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoItems = fetchAndTransformInBatches(
            TodoItem.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoSubtasks = fetchAndTransformInBatches(
            TodoSubtask.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todoTemplates = fetchAndTransformInBatches(
            TodoTemplate.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.todayAgendaOrders = fetchAndTransformInBatches(
            TodayAgendaOrder.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.80),
            "Collecting recommendations & resources\u{2026}"
        )
        payload.planningRecommendations = fetchAndTransformInBatches(
            PlanningRecommendation.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.resources = fetchAndTransformInBatches(
            Resource.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        payload.noteStudentLinks = fetchAndTransformInBatches(
            NoteStudentLink.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
    }

    // MARK: - Encode & Write

    private func encodeAndWriteExport(
        payload: BackupPayload,
        to url: URL,
        password: String?,
        progress: @escaping ProgressCallback
    ) throws -> BackupOperationSummary {
        progress(BackupProgress.progress(for: .encoding), "Encoding data\u{2026}")
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(BackupProgress.progress(for: .encoding), "Compressing data\u{2026}")
        let compressedPayloadBytes = try codec.compress(payloadBytes)

        let finalEncrypted: Data?
        let finalCompressed: Data?
        if let password, !password.isEmpty {
            progress(BackupProgress.progress(for: .encrypting), "Encrypting data\u{2026}")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalCompressed = compressedPayloadBytes
        }

        var counts = buildCoreEntityCounts(from: payload)
        counts.merge(buildExtendedEntityCounts(from: payload)) { _, new in new }

        let env = BackupServiceHelpers.buildEnvelope(
            payload: nil,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: counts,
            sha256: sha,
            notes: nil
        )

        progress(BackupProgress.progress(for: .writing), "Writing backup file\u{2026}")
        try BackupServiceHelpers.writeBackupFile(envelope: env, to: url, encoder: encoder)

        if finalEncrypted != nil {
            restrictFilePermissions(at: url)
        }

        progress(BackupProgress.progress(for: .verifying), "Verifying backup\u{2026}")
        let verificationData = try Data(contentsOf: url)
        let verificationDecoder = JSONDecoder()
        verificationDecoder.dateDecodingStrategy = .iso8601
        _ = try verificationDecoder.decode(BackupEnvelope.self, from: verificationData)

        progress(BackupProgress.progress(for: .complete), "Backup complete")
        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: BackupFile.formatVersion,
            encryptUsed: (finalEncrypted != nil),
            createdAt: Date(),
            entityCounts: counts,
            warnings: [
                "Imported documents and file attachments are not included in backups by design."
            ]
        )
    }

    private func restrictFilePermissions(at url: URL) {
        do {
            try FileManager.default.setAttributes([
                .posixPermissions: NSNumber(value: 0o600)
            ], ofItemAtPath: url.path)
        } catch {
            Self.logger.warning("Failed to set file permissions: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Entity Count Helpers

    private func buildCoreEntityCounts(from payload: BackupPayload) -> [String: Int] {
        [
            "Student": payload.students.count,
            "Lesson": payload.lessons.count,
            "LessonAssignment": payload.lessonAssignments.count,
            "Note": payload.notes.count,
            "NonSchoolDay": payload.nonSchoolDays.count,
            "SchoolDayOverride": payload.schoolDayOverrides.count,
            "StudentMeeting": payload.studentMeetings.count,
            "CommunityTopic": payload.communityTopics.count,
            "ProposedSolution": payload.proposedSolutions.count,
            "CommunityAttachment": payload.communityAttachments.count,
            "AttendanceRecord": payload.attendance.count,
            "WorkCompletionRecord": payload.workCompletions.count,
            "Project": payload.projects.count,
            "ProjectAssignmentTemplate": payload.projectAssignmentTemplates.count,
            "ProjectSession": payload.projectSessions.count,
            "ProjectRole": payload.projectRoles.count,
            "ProjectTemplateWeek": payload.projectTemplateWeeks.count,
            "ProjectWeekRoleAssignment": payload.projectWeekRoleAssignments.count
        ]
    }

    private func buildExtendedEntityCounts(from payload: BackupPayload) -> [String: Int] {
        [
            "WorkModel": payload.workModels?.count ?? 0,
            "WorkCheckIn": payload.workCheckIns?.count ?? 0,
            "WorkStep": payload.workSteps?.count ?? 0,
            "WorkParticipantEntity": payload.workParticipants?.count ?? 0,
            "PracticeSession": payload.practiceSessions?.count ?? 0,
            "LessonAttachment": payload.lessonAttachments?.count ?? 0,
            "LessonPresentation": payload.lessonPresentations?.count ?? 0,
            "SampleWork": payload.sampleWorks?.count ?? 0,
            "SampleWorkStep": payload.sampleWorkSteps?.count ?? 0,
            "NoteTemplate": payload.noteTemplates?.count ?? 0,
            "MeetingTemplate": payload.meetingTemplates?.count ?? 0,
            "Reminder": payload.reminders?.count ?? 0,
            "CalendarEvent": payload.calendarEvents?.count ?? 0,
            "Track": payload.tracks?.count ?? 0,
            "TrackStep": payload.trackSteps?.count ?? 0,
            "StudentTrackEnrollment": payload.studentTrackEnrollments?.count ?? 0,
            "GroupTrack": payload.groupTracks?.count ?? 0,
            "Document": payload.documents?.count ?? 0,
            "Supply": payload.supplies?.count ?? 0,
            "SupplyTransaction": payload.supplyTransactions?.count ?? 0,
            "Procedure": payload.procedures?.count ?? 0,
            "Schedule": payload.schedules?.count ?? 0,
            "ScheduleSlot": payload.scheduleSlots?.count ?? 0,
            "Issue": payload.issues?.count ?? 0,
            "IssueAction": payload.issueActions?.count ?? 0,
            "DevelopmentSnapshot": payload.developmentSnapshots?.count ?? 0,
            "TodoItem": payload.todoItems?.count ?? 0,
            "TodoSubtask": payload.todoSubtasks?.count ?? 0,
            "TodoTemplate": payload.todoTemplates?.count ?? 0,
            "TodayAgendaOrder": payload.todayAgendaOrders?.count ?? 0,
            "PlanningRecommendation": payload.planningRecommendations?.count ?? 0,
            "Resource": payload.resources?.count ?? 0,
            "NoteStudentLink": payload.noteStudentLinks?.count ?? 0
        ]
    }

    // MARK: - Batched Fetch Utilities

    /// Modern batched fetch that processes entities in memory-efficient chunks.
    /// Uses FetchDescriptor with offset/limit instead of loading everything at once.
    /// The autoreleasepool ensures each batch is released before fetching the next.
    func safeFetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0

        while true {
            // Use autoreleasepool to release each batch's memory after processing
            let batch: [T]? = autoreleasepool {
                var descriptor = FetchDescriptor<T>()
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize
                do {
                    return try context.fetch(descriptor)
                } catch {
                    let typeName = String(describing: T.self)
                    let desc = error.localizedDescription
                    Self.logger.warning(
                        "Batch fetch failed \(typeName, privacy: .public): \(desc, privacy: .public)"
                    )
                    return nil
                }
            }

            guard let fetchedBatch = batch, !fetchedBatch.isEmpty else { break }
            allEntities.append(contentsOf: fetchedBatch)

            // Stop if we got fewer results than requested (end of data)
            if fetchedBatch.count < batchSize { break }
            offset += batchSize
        }

        return allEntities
    }

    /// Modern fetch-and-transform pattern that converts entities to DTOs in batches.
    /// This reduces peak memory usage by not holding both models and DTOs simultaneously.
    func fetchAndTransformInBatches<T: PersistentModel, DTO>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000,
        transform: ([T]) -> [DTO]
    ) -> [DTO] {
        var allDTOs: [DTO] = []
        var offset = 0

        while true {
            // Fetch, transform, and release in one autoreleasepool
            let dtos: [DTO]? = autoreleasepool {
                var descriptor = FetchDescriptor<T>()
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
