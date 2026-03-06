import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import Compression

// MARK: - Data Collection & Export Pipeline

extension BackupService {

    func performExport(
        modelContext: ModelContext,
        to url: URL,
        password: String?,
        progress: @escaping ProgressCallback
    ) throws -> BackupOperationSummary {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students\u{2026}")

        // Modern approach: Fetch and transform to DTOs in batches to reduce peak memory usage
        // This avoids holding both full models and DTOs in memory simultaneously
        let studentDTOs = fetchAndTransformInBatches(
            Student.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.06),
            "Collecting lessons\u{2026}"
        )
        let lessonDTOs = fetchAndTransformInBatches(
            Lesson.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        // LegacyPresentation removed -- no longer exported in new backups
        let legacyPresentationDTOs: [LegacyPresentationDTO] = []
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.15),
            "Collecting lesson assignments\u{2026}"
        )
        let lessonAssignmentDTOs = fetchAndTransformInBatches(
            LessonAssignment.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.24),
            "Collecting notes\u{2026}"
        )
        let noteDTOs = fetchAndTransformInBatches(
            Note.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.27),
            "Collecting calendar data\u{2026}"
        )
        let nonSchoolDTOs = fetchAndTransformInBatches(
            NonSchoolDay.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let schoolOverrideDTOs = fetchAndTransformInBatches(
            SchoolDayOverride.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.30),
            "Collecting meetings\u{2026}"
        )
        let studentMeetingDTOs = fetchAndTransformInBatches(
            StudentMeeting.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.33),
            "Collecting community data\u{2026}"
        )
        let topicDTOs = fetchAndTransformInBatches(
            CommunityTopic.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let solutionDTOs = fetchAndTransformInBatches(
            ProposedSolution.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let attachmentDTOs = fetchAndTransformInBatches(
            CommunityAttachment.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.36),
            "Collecting attendance and work completions\u{2026}"
        )
        let attendanceDTOs = fetchAndTransformInBatches(
            AttendanceRecord.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let workCompletionDTOs = fetchAndTransformInBatches(
            WorkCompletionRecord.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.39),
            "Collecting projects\u{2026}"
        )
        let projectDTOs = fetchAndTransformInBatches(
            Project.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let projectTemplateDTOs = fetchAndTransformInBatches(
            ProjectAssignmentTemplate.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let projectSessionDTOs = fetchAndTransformInBatches(
            ProjectSession.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let projectRoleDTOs = fetchAndTransformInBatches(
            ProjectRole.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let projectWeekDTOs = fetchAndTransformInBatches(
            ProjectTemplateWeek.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }
        let projectWeekAssignDTOs = fetchAndTransformInBatches(
            ProjectWeekRoleAssignment.self, using: modelContext
        ) { BackupServiceHelpers.toDTOs($0) }

        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.42),
            "Collecting work tracking\u{2026}"
        )
        let workCheckInDTOs = fetchAndTransformInBatches(
            WorkCheckIn.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let workStepDTOs = fetchAndTransformInBatches(
            WorkStep.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let workParticipantDTOs = fetchAndTransformInBatches(
            WorkParticipantEntity.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let practiceSessionDTOs = fetchAndTransformInBatches(
            PracticeSession.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.50),
            "Collecting lesson extras\u{2026}"
        )
        let lessonAttachmentDTOs = fetchAndTransformInBatches(
            LessonAttachment.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let lessonPresentationDTOs = fetchAndTransformInBatches(
            LessonPresentation.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let sampleWorkDTOs = fetchAndTransformInBatches(
            SampleWork.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let sampleWorkStepDTOs = fetchAndTransformInBatches(
            SampleWorkStep.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.55),
            "Collecting templates & tracks\u{2026}"
        )
        let noteTemplateDTOs = fetchAndTransformInBatches(
            NoteTemplate.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let meetingTemplateDTOs = fetchAndTransformInBatches(
            MeetingTemplate.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let reminderDTOs = fetchAndTransformInBatches(
            Reminder.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let calendarEventDTOs = fetchAndTransformInBatches(
            CalendarEvent.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let trackDTOs = fetchAndTransformInBatches(
            Track.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let trackStepDTOs = fetchAndTransformInBatches(
            TrackStep.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let enrollmentDTOs = fetchAndTransformInBatches(
            StudentTrackEnrollment.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let groupTrackDTOs = fetchAndTransformInBatches(
            GroupTrack.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.65),
            "Collecting supplies, schedules & issues\u{2026}"
        )
        let documentDTOs = fetchAndTransformInBatches(
            Document.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let supplyDTOs = fetchAndTransformInBatches(
            Supply.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let supplyTransactionDTOs = fetchAndTransformInBatches(
            SupplyTransaction.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let procedureDTOs = fetchAndTransformInBatches(
            Procedure.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let scheduleDTOs = fetchAndTransformInBatches(
            Schedule.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let scheduleSlotDTOs = fetchAndTransformInBatches(
            ScheduleSlot.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let issueDTOs = fetchAndTransformInBatches(
            Issue.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let issueActionDTOs = fetchAndTransformInBatches(
            IssueAction.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        progress(
            BackupProgress.progress(for: .collecting, subProgress: 0.75),
            "Collecting snapshots & todos\u{2026}"
        )
        let snapshotDTOs = fetchAndTransformInBatches(
            DevelopmentSnapshot.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let todoItemDTOs = fetchAndTransformInBatches(
            TodoItem.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let todoSubtaskDTOs = fetchAndTransformInBatches(
            TodoSubtask.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let todoTemplateDTOs = fetchAndTransformInBatches(
            TodoTemplate.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }
        let agendaOrderDTOs = fetchAndTransformInBatches(
            TodayAgendaOrder.self, using: modelContext
        ) { BackupDTOTransformers.toDTOs($0) }

        let preferences = buildPreferencesDTO()

        var payload = BackupPayload(
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

        // Format v8+ entity arrays
        payload.workCheckIns = workCheckInDTOs
        payload.workSteps = workStepDTOs
        payload.workParticipants = workParticipantDTOs
        payload.practiceSessions = practiceSessionDTOs
        payload.lessonAttachments = lessonAttachmentDTOs
        payload.lessonPresentations = lessonPresentationDTOs
        payload.sampleWorks = sampleWorkDTOs
        payload.sampleWorkSteps = sampleWorkStepDTOs
        payload.noteTemplates = noteTemplateDTOs
        payload.meetingTemplates = meetingTemplateDTOs
        payload.reminders = reminderDTOs
        payload.calendarEvents = calendarEventDTOs
        payload.tracks = trackDTOs
        payload.trackSteps = trackStepDTOs
        payload.studentTrackEnrollments = enrollmentDTOs
        payload.groupTracks = groupTrackDTOs
        payload.documents = documentDTOs
        payload.supplies = supplyDTOs
        payload.supplyTransactions = supplyTransactionDTOs
        payload.procedures = procedureDTOs
        payload.schedules = scheduleDTOs
        payload.scheduleSlots = scheduleSlotDTOs
        payload.issues = issueDTOs
        payload.issueActions = issueActionDTOs
        payload.developmentSnapshots = snapshotDTOs
        payload.todoItems = todoItemDTOs
        payload.todoSubtasks = todoSubtaskDTOs
        payload.todoTemplates = todoTemplateDTOs
        payload.todayAgendaOrders = agendaOrderDTOs

        progress(BackupProgress.progress(for: .encoding), "Encoding data\u{2026}")
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(BackupProgress.progress(for: .encoding), "Compressing data\u{2026}")
        let compressedPayloadBytes = try codec.compress(payloadBytes)

        let finalPayload: BackupPayload?
        let finalEncrypted: Data?
        let finalCompressed: Data?

        if let password = password, !password.isEmpty {
            progress(BackupProgress.progress(for: .encrypting), "Encrypting data\u{2026}")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalPayload = nil
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalPayload = nil
            finalCompressed = compressedPayloadBytes
        }

        var counts: [String: Int] = [
            "Student": studentDTOs.count,
            "Lesson": lessonDTOs.count,
            "LegacyPresentation": legacyPresentationDTOs.count,
            "LessonAssignment": lessonAssignmentDTOs.count,
            "Note": noteDTOs.count,
            "NonSchoolDay": nonSchoolDTOs.count,
            "SchoolDayOverride": schoolOverrideDTOs.count,
            "StudentMeeting": studentMeetingDTOs.count,
            "CommunityTopic": topicDTOs.count,
            "ProposedSolution": solutionDTOs.count,
            "CommunityAttachment": attachmentDTOs.count,
            "AttendanceRecord": attendanceDTOs.count,
            "WorkCompletionRecord": workCompletionDTOs.count,
            "Project": projectDTOs.count,
            "ProjectAssignmentTemplate": projectTemplateDTOs.count,
            "ProjectSession": projectSessionDTOs.count,
            "ProjectRole": projectRoleDTOs.count,
            "ProjectTemplateWeek": projectWeekDTOs.count,
            "ProjectWeekRoleAssignment": projectWeekAssignDTOs.count
        ]
        // Format v8+ counts
        counts["WorkCheckIn"] = workCheckInDTOs.count
        counts["WorkStep"] = workStepDTOs.count
        counts["WorkParticipantEntity"] = workParticipantDTOs.count
        counts["PracticeSession"] = practiceSessionDTOs.count
        counts["LessonAttachment"] = lessonAttachmentDTOs.count
        counts["LessonPresentation"] = lessonPresentationDTOs.count
        counts["SampleWork"] = sampleWorkDTOs.count
        counts["SampleWorkStep"] = sampleWorkStepDTOs.count
        counts["NoteTemplate"] = noteTemplateDTOs.count
        counts["MeetingTemplate"] = meetingTemplateDTOs.count
        counts["Reminder"] = reminderDTOs.count
        counts["CalendarEvent"] = calendarEventDTOs.count
        counts["Track"] = trackDTOs.count
        counts["TrackStep"] = trackStepDTOs.count
        counts["StudentTrackEnrollment"] = enrollmentDTOs.count
        counts["GroupTrack"] = groupTrackDTOs.count
        counts["Document"] = documentDTOs.count
        counts["Supply"] = supplyDTOs.count
        counts["SupplyTransaction"] = supplyTransactionDTOs.count
        counts["Procedure"] = procedureDTOs.count
        counts["Schedule"] = scheduleDTOs.count
        counts["ScheduleSlot"] = scheduleSlotDTOs.count
        counts["Issue"] = issueDTOs.count
        counts["IssueAction"] = issueActionDTOs.count
        counts["DevelopmentSnapshot"] = snapshotDTOs.count
        counts["TodoItem"] = todoItemDTOs.count
        counts["TodoSubtask"] = todoSubtaskDTOs.count
        counts["TodoTemplate"] = todoTemplateDTOs.count
        counts["TodayAgendaOrder"] = agendaOrderDTOs.count

        let env = BackupServiceHelpers.buildEnvelope(
            payload: finalPayload,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: counts,
            sha256: sha,
            notes: nil
        )

        progress(BackupProgress.progress(for: .writing), "Writing backup file\u{2026}")
        try BackupServiceHelpers.writeBackupFile(envelope: env, to: url, encoder: encoder)

        if finalEncrypted != nil {
            do {
                try FileManager.default.setAttributes([
                    .posixPermissions: NSNumber(value: 0o600)
                ], ofItemAtPath: url.path)
            } catch {
                print("\u{26a0}\u{fe0f} [Backup:exportBackup] Failed to set file permissions: \(error)")
            }
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
                    // swiftlint:disable:next line_length
                    print("\u{26a0}\u{fe0f} [Backup:safeFetchInBatches] Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
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
                    // swiftlint:disable:next line_length
                    print("\u{26a0}\u{fe0f} [Backup:collectBatch] Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
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
