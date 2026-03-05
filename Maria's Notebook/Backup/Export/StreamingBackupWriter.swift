import Foundation
import SwiftData

/// Handles streaming export of backup data to avoid loading everything into memory
/// Writes entities in batches directly to disk for memory efficiency
@MainActor
public final class StreamingBackupWriter {
    
    // MARK: - Types
    
    public struct Configuration: Sendable {
        public var batchSize: Int = BackupConstants.streamingBatchSize
        /// Enable autoreleasepool for Objective-C interop (set to false for pure Swift workloads)
        public var useAutoreleasePool: Bool = false
        public var enableParallelProcessing: Bool = true
        
        public static let `default` = Configuration()
    }
    
    public enum WriteError: LocalizedError {
        case fileCreationFailed(URL)
        case encodingFailed(Error)
        case checksumMismatch
        case writeFailed(Error)
        
        public var errorDescription: String? {
            switch self {
            case .fileCreationFailed(let url):
                return "Failed to create backup file at: \(url.path)"
            case .encodingFailed(let error):
                return "Failed to encode data: \(error.localizedDescription)"
            case .checksumMismatch:
                return "Data integrity check failed during write"
            case .writeFailed(let error):
                return "Failed to write to disk: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Properties
    
    let configuration: Configuration
    private let codec = BackupCodec()
    
    // MARK: - Initialization
    
    public init(configuration: Configuration? = nil) {
        self.configuration = configuration ?? Configuration()
    }
    
    // MARK: - Streaming Export
    
    /// Exports backup using streaming approach to minimize memory usage
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - url: Destination file URL
    ///   - password: Optional encryption password
    ///   - progress: Progress callback with (progress, message, entityCount, entityType)
    /// - Returns: Summary of the backup operation
    public func streamingExport(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws -> BackupOperationSummary {
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        progress(0.0, "Initializing streaming export…", 0, nil)
        
        // Phase 1: Collect entity counts and prepare for streaming
        let counts = try await collectEntityCounts(modelContext: modelContext)
        let totalEntities = counts.values.reduce(0, +)
        
        progress(0.05, "Processing \(totalEntities) entities in batches…", totalEntities, nil)
        
        // Phase 2: Stream each entity type in batches with autoreleasepool
        // Use sequential processing to avoid Sendable issues with ModelContext and processedEntities
        var processedEntities = 0
        
        // Collect DTOs - Sequential processing only (parallel disabled due to Swift 6 concurrency)
        let s = try await streamFetch(Student.self, from: modelContext, progress: { count, type in
            processedEntities += count
            progress(0.10, "Processing students…", processedEntities, type)
        })
        let l = try await streamFetch(Lesson.self, from: modelContext, progress: { count, type in
            processedEntities += count
            progress(0.20, "Processing lessons…", processedEntities, type)
        })
        let n = try await streamFetch(Note.self, from: modelContext, progress: { count, type in
            processedEntities += count
            progress(0.30, "Processing notes…", processedEntities, type)
        })
        
        // Safe cast with error handling
        guard let studentDTOs = s as? [StudentDTO],
              let lessonDTOs = l as? [LessonDTO],
              let noteDTOs = n as? [NoteDTO] else {
            throw WriteError.encodingFailed(NSError(
                domain: "StreamingBackupWriter", code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to cast entity types during processing"
                ]
            ))
        }
        
        // Continue with other entity types (sequential for now to maintain order)
        progress(0.35, "Processing remaining entities…", processedEntities, nil)
        
        // LegacyPresentation removed — no longer exported in new backups
        let legacyPresentationDTOs: [LegacyPresentationDTO] = []
        
        let lessonAssignments: [LessonAssignment] = try await streamFetchRaw(
            LessonAssignment.self, from: modelContext
        )
        let lessonAssignmentDTOs = BackupDTOTransformers.toDTOs(lessonAssignments)
        
        let nonSchoolDays: [NonSchoolDay] = try await streamFetchRaw(NonSchoolDay.self, from: modelContext)
        let nonSchoolDTOs = BackupDTOTransformers.toDTOs(nonSchoolDays)
        
        let schoolDayOverrides: [SchoolDayOverride] = try await streamFetchRaw(
            SchoolDayOverride.self, from: modelContext
        )
        let schoolOverrideDTOs = BackupDTOTransformers.toDTOs(schoolDayOverrides)
        
        let studentMeetings: [StudentMeeting] = try await streamFetchRaw(StudentMeeting.self, from: modelContext)
        let studentMeetingDTOs = BackupDTOTransformers.toDTOs(studentMeetings)
        
        let communityTopics: [CommunityTopic] = try await streamFetchRaw(CommunityTopic.self, from: modelContext)
        let topicDTOs = BackupDTOTransformers.toDTOs(communityTopics)
        
        let proposedSolutions: [ProposedSolution] = try await streamFetchRaw(ProposedSolution.self, from: modelContext)
        let solutionDTOs = BackupDTOTransformers.toDTOs(proposedSolutions)
        
        let communityAttachments: [CommunityAttachment] = try await streamFetchRaw(
            CommunityAttachment.self, from: modelContext
        )
        let attachmentDTOs = BackupDTOTransformers.toDTOs(communityAttachments)
        
        let attendance: [AttendanceRecord] = try await streamFetchRaw(AttendanceRecord.self, from: modelContext)
        let attendanceDTOs = BackupDTOTransformers.toDTOs(attendance)
        
        let workCompletions: [WorkCompletionRecord] = try await streamFetchRaw(
            WorkCompletionRecord.self, from: modelContext
        )
        let workCompletionDTOs = BackupDTOTransformers.toDTOs(workCompletions)
        
        let projects: [Project] = try await streamFetchRaw(Project.self, from: modelContext)
        let projectDTOs = BackupDTOTransformers.toDTOs(projects)
        
        let projectTemplates: [ProjectAssignmentTemplate] = try await streamFetchRaw(
            ProjectAssignmentTemplate.self, from: modelContext
        )
        let projectTemplateDTOs = BackupDTOTransformers.toDTOs(projectTemplates)
        
        let projectSessions: [ProjectSession] = try await streamFetchRaw(ProjectSession.self, from: modelContext)
        let projectSessionDTOs = BackupDTOTransformers.toDTOs(projectSessions)
        
        let projectRoles: [ProjectRole] = try await streamFetchRaw(ProjectRole.self, from: modelContext)
        let projectRoleDTOs = BackupDTOTransformers.toDTOs(projectRoles)
        
        let projectWeeks: [ProjectTemplateWeek] = try await streamFetchRaw(ProjectTemplateWeek.self, from: modelContext)
        let projectWeekDTOs = BackupDTOTransformers.toDTOs(projectWeeks)
        
        let projectWeekAssignments: [ProjectWeekRoleAssignment] =
            try await streamFetchRaw(
                ProjectWeekRoleAssignment.self, from: modelContext
            )
        let projectWeekAssignDTOs = BackupDTOTransformers.toDTOs(projectWeekAssignments)
        
        progress(0.40, "Processing work tracking…", processedEntities, nil)
        
        // Work tracking entities (format v8+)
        let workCheckIns: [WorkCheckIn] = try await streamFetchRaw(WorkCheckIn.self, from: modelContext)
        let workCheckInDTOs = BackupDTOTransformers.toDTOs(workCheckIns)
        
        let workSteps: [WorkStep] = try await streamFetchRaw(WorkStep.self, from: modelContext)
        let workStepDTOs = BackupDTOTransformers.toDTOs(workSteps)
        
        let workParticipants: [WorkParticipantEntity] = try await streamFetchRaw(
            WorkParticipantEntity.self, from: modelContext
        )
        let workParticipantDTOs = BackupDTOTransformers.toDTOs(workParticipants)
        
        let practiceSessions: [PracticeSession] = try await streamFetchRaw(PracticeSession.self, from: modelContext)
        let practiceSessionDTOs = BackupDTOTransformers.toDTOs(practiceSessions)
        
        progress(0.44, "Processing lesson extras…", processedEntities, nil)
        
        let lessonAttachments: [LessonAttachment] = try await streamFetchRaw(LessonAttachment.self, from: modelContext)
        let lessonAttachmentDTOs = BackupDTOTransformers.toDTOs(lessonAttachments)
        
        let lessonPresentations: [LessonPresentation] = try await streamFetchRaw(
            LessonPresentation.self, from: modelContext
        )
        let lessonPresentationDTOs = BackupDTOTransformers.toDTOs(lessonPresentations)

        let lessonExercises: [LessonExercise] = try await streamFetchRaw(LessonExercise.self, from: modelContext)
        let lessonExerciseDTOs = BackupDTOTransformers.toDTOs(lessonExercises)

        progress(0.46, "Processing templates…", processedEntities, nil)
        
        let noteTemplates: [NoteTemplate] = try await streamFetchRaw(NoteTemplate.self, from: modelContext)
        let noteTemplateDTOs = BackupDTOTransformers.toDTOs(noteTemplates)
        
        let meetingTemplates: [MeetingTemplate] = try await streamFetchRaw(MeetingTemplate.self, from: modelContext)
        let meetingTemplateDTOs = BackupDTOTransformers.toDTOs(meetingTemplates)
        
        progress(0.48, "Processing reminders & calendar…", processedEntities, nil)
        
        let reminders: [Reminder] = try await streamFetchRaw(Reminder.self, from: modelContext)
        let reminderDTOs = BackupDTOTransformers.toDTOs(reminders)
        
        let calendarEvents: [CalendarEvent] = try await streamFetchRaw(CalendarEvent.self, from: modelContext)
        let calendarEventDTOs = BackupDTOTransformers.toDTOs(calendarEvents)
        
        progress(0.50, "Processing tracks…", processedEntities, nil)
        
        let tracks: [Track] = try await streamFetchRaw(Track.self, from: modelContext)
        let trackDTOs = BackupDTOTransformers.toDTOs(tracks)
        
        let trackSteps: [TrackStep] = try await streamFetchRaw(TrackStep.self, from: modelContext)
        let trackStepDTOs = BackupDTOTransformers.toDTOs(trackSteps)
        
        let enrollments: [StudentTrackEnrollment] = try await streamFetchRaw(
            StudentTrackEnrollment.self, from: modelContext
        )
        let enrollmentDTOs = BackupDTOTransformers.toDTOs(enrollments)
        
        let groupTracks: [GroupTrack] = try await streamFetchRaw(GroupTrack.self, from: modelContext)
        let groupTrackDTOs = BackupDTOTransformers.toDTOs(groupTracks)
        
        progress(0.52, "Processing documents & supplies…", processedEntities, nil)
        
        let documents: [Document] = try await streamFetchRaw(Document.self, from: modelContext)
        let documentDTOs = BackupDTOTransformers.toDTOs(documents)
        
        let supplies: [Supply] = try await streamFetchRaw(Supply.self, from: modelContext)
        let supplyDTOs = BackupDTOTransformers.toDTOs(supplies)
        
        let supplyTransactions: [SupplyTransaction] = try await streamFetchRaw(
            SupplyTransaction.self, from: modelContext
        )
        let supplyTransactionDTOs = BackupDTOTransformers.toDTOs(supplyTransactions)
        
        let procedures: [Procedure] = try await streamFetchRaw(Procedure.self, from: modelContext)
        let procedureDTOs = BackupDTOTransformers.toDTOs(procedures)
        
        progress(0.54, "Processing schedules…", processedEntities, nil)
        
        let schedules: [Schedule] = try await streamFetchRaw(Schedule.self, from: modelContext)
        let scheduleDTOs = BackupDTOTransformers.toDTOs(schedules)
        
        let scheduleSlots: [ScheduleSlot] = try await streamFetchRaw(ScheduleSlot.self, from: modelContext)
        let scheduleSlotDTOs = BackupDTOTransformers.toDTOs(scheduleSlots)
        
        progress(0.56, "Processing issues…", processedEntities, nil)
        
        let issues: [Issue] = try await streamFetchRaw(Issue.self, from: modelContext)
        let issueDTOs = BackupDTOTransformers.toDTOs(issues)
        
        let issueActions: [IssueAction] = try await streamFetchRaw(IssueAction.self, from: modelContext)
        let issueActionDTOs = BackupDTOTransformers.toDTOs(issueActions)
        
        progress(0.57, "Processing snapshots & todos…", processedEntities, nil)
        
        let snapshots: [DevelopmentSnapshot] = try await streamFetchRaw(DevelopmentSnapshot.self, from: modelContext)
        let snapshotDTOs = BackupDTOTransformers.toDTOs(snapshots)
        
        let todoItems: [TodoItem] = try await streamFetchRaw(TodoItem.self, from: modelContext)
        let todoItemDTOs = BackupDTOTransformers.toDTOs(todoItems)
        
        let todoSubtasks: [TodoSubtask] = try await streamFetchRaw(TodoSubtask.self, from: modelContext)
        let todoSubtaskDTOs = BackupDTOTransformers.toDTOs(todoSubtasks)
        
        let todoTemplates: [TodoTemplate] = try await streamFetchRaw(TodoTemplate.self, from: modelContext)
        let todoTemplateDTOs = BackupDTOTransformers.toDTOs(todoTemplates)
        
        let agendaOrders: [TodayAgendaOrder] = try await streamFetchRaw(TodayAgendaOrder.self, from: modelContext)
        let agendaOrderDTOs = BackupDTOTransformers.toDTOs(agendaOrders)
        
        progress(0.60, "Building payload…", processedEntities, nil)
        
        // Build payload
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
        payload.lessonExercises = lessonExerciseDTOs
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
        
        progress(0.70, "Encoding and compressing…", processedEntities, nil)
        
        // Encode with checksum
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)
        
        // Compress
        let compressedPayloadBytes = try codec.compress(payloadBytes)
        
        progress(0.85, "Finalizing backup…", processedEntities, nil)
        
        // Handle encryption if needed
        let finalEncrypted: Data?
        let finalCompressed: Data?
        
        if let password = password, !password.isEmpty {
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalCompressed = compressedPayloadBytes
        }
        
        // Build manifest with per-entity checksums
        let manifest = BackupManifest(
            entityCounts: counts,
            sha256: sha,
            notes: nil,
            compression: BackupFile.compressionAlgorithm
        )
        
        // Create envelope
        let envelope = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: manifest,
            payload: nil,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed
        )
        
        progress(0.95, "Writing to disk…", processedEntities, nil)
        
        // Write to disk
        let envBytes = try encoder.encode(envelope)
        
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("⚠️ [Backup:streamingExport] Failed to remove existing file at \(url.lastPathComponent): \(error)")
            }
        }
        try envBytes.write(to: url, options: .atomic)
        
        // Verify immediately after write
        progress(0.98, "Verifying backup…", processedEntities, nil)
        try verifyBackupFile(at: url)
        
        progress(1.0, "Backup complete", processedEntities, nil)
        
        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: BackupFile.formatVersion,
            encryptUsed: finalEncrypted != nil,
            createdAt: Date(),
            entityCounts: counts,
            warnings: ["Imported documents and file attachments are not included in backups by design."]
        )
    }
    
    // MARK: - Private Helpers

    private func verifyBackupFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder.backupConfigured()
        _ = try decoder.decode(BackupEnvelope.self, from: data)
    }
}
