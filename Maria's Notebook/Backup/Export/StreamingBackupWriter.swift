// swiftlint:disable file_length
import Foundation
import CoreData
import OSLog

/// Mutable collector for streaming export to avoid `inout` across `async` boundaries
@MainActor
private final class StreamCollector {
    var payload: BackupPayload
    var processedEntities = 0

    init(preferences: PreferencesDTO) {
        payload = BackupPayload(
            items: [], students: [], lessons: [],
            lessonAssignments: [],
            notes: [], nonSchoolDays: [], schoolDayOverrides: [],
            studentMeetings: [], communityTopics: [],
            proposedSolutions: [], communityAttachments: [],
            attendance: [], workCompletions: [],
            projects: [], projectAssignmentTemplates: [],
            projectSessions: [], projectRoles: [],
            projectTemplateWeeks: [], projectWeekRoleAssignments: [],
            preferences: preferences
        )
    }
}

// swiftlint:disable type_body_length
/// Handles streaming export of backup data to avoid loading everything into memory
/// Writes entities in batches directly to disk for memory efficiency
@MainActor
public final class StreamingBackupWriter {
    private static let logger = Logger.backup

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
    public func streamingExport(
        viewContext: NSManagedObjectContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws -> BackupOperationSummary {

        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.0, "Initializing streaming export\u{2026}", 0, nil)

        let counts = try await collectEntityCounts(viewContext: viewContext)
        let totalEntities = counts.values.reduce(0, +)
        progress(0.05, "Processing \(totalEntities) entities in batches\u{2026}", totalEntities, nil)

        let collector = StreamCollector(preferences: buildPreferencesDTO())
        try await streamCoreEntities(into: collector, from: viewContext, progress: progress)
        try await streamRelationEntities(into: collector, from: viewContext, progress: progress)
        try await streamV8Entities(into: collector, from: viewContext, progress: progress)
        try await streamExtraEntities(into: collector, from: viewContext, progress: progress)

        progress(0.60, "Building payload\u{2026}", collector.processedEntities, nil)

        return try finalizeStreamingExport(
            payload: collector.payload, counts: counts, to: url,
            password: password, progress: progress,
            processedEntities: collector.processedEntities
        )
    }

    // MARK: - Collection Helpers

    private func streamCoreEntities(
        into collector: StreamCollector,
        from viewContext: NSManagedObjectContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        let s = try await streamFetch(CDStudent.self, from: viewContext, progress: { count, type in
            collector.processedEntities += count
            progress(0.10, "Processing students\u{2026}", collector.processedEntities, type)
        })
        let l = try await streamFetch(CDLesson.self, from: viewContext, progress: { count, type in
            collector.processedEntities += count
            progress(0.20, "Processing lessons\u{2026}", collector.processedEntities, type)
        })
        let n = try await streamFetch(CDNote.self, from: viewContext, progress: { count, type in
            collector.processedEntities += count
            progress(0.30, "Processing notes\u{2026}", collector.processedEntities, type)
        })

        guard let studentDTOs = s as? [StudentDTO],
              let lessonDTOs = l as? [LessonDTO],
              let noteDTOs = n as? [NoteDTO] else {
            throw WriteError.encodingFailed(NSError(
                domain: "StreamingBackupWriter", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to cast entity types during processing"]
            ))
        }

        collector.payload.students = studentDTOs
        collector.payload.lessons = lessonDTOs
        collector.payload.notes = noteDTOs
    }

    private func streamRelationEntities(
        into collector: StreamCollector,
        from viewContext: NSManagedObjectContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.35, "Processing remaining entities\u{2026}", collector.processedEntities, nil)

        // LegacyPresentation removed — no longer exported in new backups

        let lessonAssignments: [CDLessonAssignment] = try await streamFetchRaw(CDLessonAssignment.self, from: viewContext)
        collector.payload.lessonAssignments = BackupDTOTransformers.toDTOs(lessonAssignments)

        let nonSchoolDays: [CDNonSchoolDay] = try await streamFetchRaw(CDNonSchoolDay.self, from: viewContext)
        collector.payload.nonSchoolDays = BackupDTOTransformers.toDTOs(nonSchoolDays)

        let schoolDayOverrides: [CDSchoolDayOverride] =
            try await streamFetchRaw(CDSchoolDayOverride.self, from: viewContext)
        collector.payload.schoolDayOverrides = BackupDTOTransformers.toDTOs(schoolDayOverrides)

        let studentMeetings: [CDStudentMeeting] = try await streamFetchRaw(CDStudentMeeting.self, from: viewContext)
        collector.payload.studentMeetings = BackupDTOTransformers.toDTOs(studentMeetings)

        let communityTopics: [CDCommunityTopicEntity] = try await streamFetchRaw(CDCommunityTopicEntity.self, from: viewContext)
        collector.payload.communityTopics = BackupDTOTransformers.toDTOs(communityTopics)

        let proposedSolutions: [CDProposedSolutionEntity] = try await streamFetchRaw(CDProposedSolutionEntity.self, from: viewContext)
        collector.payload.proposedSolutions = BackupDTOTransformers.toDTOs(proposedSolutions)

        let communityAttachments: [CDCommunityAttachmentEntity] = try await streamFetchRaw(
            CDCommunityAttachmentEntity.self, from: viewContext
        )
        collector.payload.communityAttachments = BackupDTOTransformers.toDTOs(communityAttachments)

        let attendance: [CDAttendanceRecord] = try await streamFetchRaw(CDAttendanceRecord.self, from: viewContext)
        collector.payload.attendance = BackupDTOTransformers.toDTOs(attendance)

        let workCompletions: [CDWorkCompletionRecord] = try await streamFetchRaw(
            CDWorkCompletionRecord.self, from: viewContext
        )
        collector.payload.workCompletions = BackupDTOTransformers.toDTOs(workCompletions)

        let projects: [CDProject] = try await streamFetchRaw(CDProject.self, from: viewContext)
        collector.payload.projects = BackupDTOTransformers.toDTOs(projects)

        let projectTemplates: [CDProjectAssignmentTemplate] = try await streamFetchRaw(
            CDProjectAssignmentTemplate.self, from: viewContext
        )
        collector.payload.projectAssignmentTemplates = BackupDTOTransformers.toDTOs(projectTemplates)

        let projectSessions: [CDProjectSession] = try await streamFetchRaw(CDProjectSession.self, from: viewContext)
        collector.payload.projectSessions = BackupDTOTransformers.toDTOs(projectSessions)

        let projectRoles: [CDProjectRole] = try await streamFetchRaw(CDProjectRole.self, from: viewContext)
        collector.payload.projectRoles = BackupDTOTransformers.toDTOs(projectRoles)

        let projectWeeks: [CDProjectTemplateWeek] = try await streamFetchRaw(CDProjectTemplateWeek.self, from: viewContext)
        collector.payload.projectTemplateWeeks = BackupDTOTransformers.toDTOs(projectWeeks)

        let projectWeekAssignments: [CDProjectWeekRoleAssignment] = try await streamFetchRaw(
            CDProjectWeekRoleAssignment.self, from: viewContext
        )
        collector.payload.projectWeekRoleAssignments = BackupDTOTransformers.toDTOs(projectWeekAssignments)
    }

    private func streamV8Entities(
        into collector: StreamCollector,
        from viewContext: NSManagedObjectContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.40, "Processing work tracking\u{2026}", collector.processedEntities, nil)

        let workModels: [CDWorkModel] = try await streamFetchRaw(CDWorkModel.self, from: viewContext)
        collector.payload.workModels = BackupDTOTransformers.toDTOs(workModels)

        let workCheckIns: [CDWorkCheckIn] = try await streamFetchRaw(CDWorkCheckIn.self, from: viewContext)
        collector.payload.workCheckIns = BackupDTOTransformers.toDTOs(workCheckIns)

        let workSteps: [CDWorkStep] = try await streamFetchRaw(CDWorkStep.self, from: viewContext)
        collector.payload.workSteps = BackupDTOTransformers.toDTOs(workSteps)

        let workParticipants: [CDWorkParticipantEntity] = try await streamFetchRaw(
            CDWorkParticipantEntity.self, from: viewContext
        )
        collector.payload.workParticipants = BackupDTOTransformers.toDTOs(workParticipants)

        let practiceSessions: [CDPracticeSession] = try await streamFetchRaw(CDPracticeSession.self, from: viewContext)
        collector.payload.practiceSessions = BackupDTOTransformers.toDTOs(practiceSessions)

        progress(0.44, "Processing lesson extras\u{2026}", collector.processedEntities, nil)

        let lessonAttachments: [CDLessonAttachment] = try await streamFetchRaw(CDLessonAttachment.self, from: viewContext)
        collector.payload.lessonAttachments = BackupDTOTransformers.toDTOs(lessonAttachments)

        let lessonPresentations: [CDLessonPresentation] = try await streamFetchRaw(
            CDLessonPresentation.self, from: viewContext
        )
        collector.payload.lessonPresentations = BackupDTOTransformers.toDTOs(lessonPresentations)

        let sampleWorks: [CDSampleWork] = try await streamFetchRaw(CDSampleWork.self, from: viewContext)
        collector.payload.sampleWorks = BackupDTOTransformers.toDTOs(sampleWorks)

        let sampleWorkSteps: [CDSampleWorkStep] = try await streamFetchRaw(CDSampleWorkStep.self, from: viewContext)
        collector.payload.sampleWorkSteps = BackupDTOTransformers.toDTOs(sampleWorkSteps)
    }

    private func streamExtraEntities(
        into collector: StreamCollector,
        from viewContext: NSManagedObjectContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.46, "Processing templates\u{2026}", collector.processedEntities, nil)

        let noteTemplates: [CDNoteTemplate] = try await streamFetchRaw(CDNoteTemplate.self, from: viewContext)
        collector.payload.noteTemplates = BackupDTOTransformers.toDTOs(noteTemplates)

        let meetingTemplates: [CDMeetingTemplate] = try await streamFetchRaw(CDMeetingTemplate.self, from: viewContext)
        collector.payload.meetingTemplates = BackupDTOTransformers.toDTOs(meetingTemplates)

        progress(0.48, "Processing reminders & calendar\u{2026}", collector.processedEntities, nil)

        let reminders: [CDReminder] = try await streamFetchRaw(CDReminder.self, from: viewContext)
        collector.payload.reminders = BackupDTOTransformers.toDTOs(reminders)

        let calendarEvents: [CDCalendarEvent] = try await streamFetchRaw(CDCalendarEvent.self, from: viewContext)
        collector.payload.calendarEvents = BackupDTOTransformers.toDTOs(calendarEvents)

        progress(0.50, "Processing tracks\u{2026}", collector.processedEntities, nil)

        let tracks: [CDTrackEntity] = try await streamFetchRaw(CDTrackEntity.self, from: viewContext)
        collector.payload.tracks = BackupDTOTransformers.toDTOs(tracks)

        let trackSteps: [CDTrackStepEntity] = try await streamFetchRaw(CDTrackStepEntity.self, from: viewContext)
        collector.payload.trackSteps = BackupDTOTransformers.toDTOs(trackSteps)

        let enrollments: [CDStudentTrackEnrollmentEntity] = try await streamFetchRaw(
            CDStudentTrackEnrollmentEntity.self, from: viewContext
        )
        collector.payload.studentTrackEnrollments = BackupDTOTransformers.toDTOs(enrollments)

        let groupTracks: [CDGroupTrack] = try await streamFetchRaw(CDGroupTrack.self, from: viewContext)
        collector.payload.groupTracks = BackupDTOTransformers.toDTOs(groupTracks)

        progress(0.52, "Processing documents & supplies\u{2026}", collector.processedEntities, nil)

        let documents: [CDDocument] = try await streamFetchRaw(CDDocument.self, from: viewContext)
        collector.payload.documents = BackupDTOTransformers.toDTOs(documents)

        let supplies: [CDSupply] = try await streamFetchRaw(CDSupply.self, from: viewContext)
        collector.payload.supplies = BackupDTOTransformers.toDTOs(supplies)

        let supplyTransactions: [CDSupplyTransaction] = try await streamFetchRaw(
            CDSupplyTransaction.self, from: viewContext
        )
        collector.payload.supplyTransactions = BackupDTOTransformers.toDTOs(supplyTransactions)

        let procedures: [CDProcedure] = try await streamFetchRaw(CDProcedure.self, from: viewContext)
        collector.payload.procedures = BackupDTOTransformers.toDTOs(procedures)

        progress(0.54, "Processing schedules\u{2026}", collector.processedEntities, nil)

        let schedules: [CDSchedule] = try await streamFetchRaw(CDSchedule.self, from: viewContext)
        collector.payload.schedules = BackupDTOTransformers.toDTOs(schedules)

        let scheduleSlots: [CDScheduleSlot] = try await streamFetchRaw(CDScheduleSlot.self, from: viewContext)
        collector.payload.scheduleSlots = BackupDTOTransformers.toDTOs(scheduleSlots)

        progress(0.56, "Processing issues\u{2026}", collector.processedEntities, nil)

        let issues: [CDIssue] = try await streamFetchRaw(CDIssue.self, from: viewContext)
        collector.payload.issues = BackupDTOTransformers.toDTOs(issues)

        let issueActions: [CDIssueAction] = try await streamFetchRaw(CDIssueAction.self, from: viewContext)
        collector.payload.issueActions = BackupDTOTransformers.toDTOs(issueActions)

        try await streamSnapshotAndTodoDTOs(into: collector, from: viewContext, progress: progress)
    }

    private func streamSnapshotAndTodoDTOs(
        into collector: StreamCollector,
        from viewContext: NSManagedObjectContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.57, "Processing snapshots & todos\u{2026}", collector.processedEntities, nil)

        let snapshots: [CDDevelopmentSnapshotEntity] = try await streamFetchRaw(CDDevelopmentSnapshotEntity.self, from: viewContext)
        collector.payload.developmentSnapshots = BackupDTOTransformers.toDTOs(snapshots)

        let todoItems: [CDTodoItem] = try await streamFetchRaw(CDTodoItem.self, from: viewContext)
        collector.payload.todoItems = BackupDTOTransformers.toDTOs(todoItems)

        let todoSubtasks: [CDTodoSubtask] = try await streamFetchRaw(CDTodoSubtask.self, from: viewContext)
        collector.payload.todoSubtasks = BackupDTOTransformers.toDTOs(todoSubtasks)

        let todoTemplates: [CDTodoTemplate] = try await streamFetchRaw(CDTodoTemplate.self, from: viewContext)
        collector.payload.todoTemplates = BackupDTOTransformers.toDTOs(todoTemplates)

        let agendaOrders: [CDTodayAgendaOrder] = try await streamFetchRaw(CDTodayAgendaOrder.self, from: viewContext)
        collector.payload.todayAgendaOrders = BackupDTOTransformers.toDTOs(agendaOrders)

        progress(0.58, "Processing recommendations & resources\u{2026}", collector.processedEntities, nil)

        let recommendations: [CDPlanningRecommendation] = try await streamFetchRaw(
            CDPlanningRecommendation.self, from: viewContext
        )
        collector.payload.planningRecommendations = BackupDTOTransformers.toDTOs(recommendations)

        let resources: [CDResource] = try await streamFetchRaw(CDResource.self, from: viewContext)
        collector.payload.resources = BackupDTOTransformers.toDTOs(resources)

        let noteStudentLinks: [CDNoteStudentLink] = try await streamFetchRaw(CDNoteStudentLink.self, from: viewContext)
        collector.payload.noteStudentLinks = BackupDTOTransformers.toDTOs(noteStudentLinks)
    }

    // MARK: - Finalization

    // swiftlint:disable:next function_parameter_count
    private func finalizeStreamingExport(
        payload: BackupPayload,
        counts: [String: Int],
        to url: URL,
        password: String?,
        progress: @escaping (Double, String, Int, String?) -> Void,
        processedEntities: Int
    ) throws -> BackupOperationSummary {
        progress(0.70, "Encoding and compressing\u{2026}", processedEntities, nil)

        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)
        let compressedPayloadBytes = try codec.compress(payloadBytes)

        progress(0.85, "Finalizing backup\u{2026}", processedEntities, nil)

        let finalEncrypted: Data?
        let finalCompressed: Data?
        if let password, !password.isEmpty {
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalCompressed = compressedPayloadBytes
        }

        let manifest = BackupManifest(
            entityCounts: counts, sha256: sha,
            notes: nil, compression: BackupFile.compressionAlgorithm
        )

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

        progress(0.95, "Writing to disk\u{2026}", processedEntities, nil)
        try writeEnvelopeToDisk(envelope, to: url, encoder: encoder)

        progress(0.98, "Verifying backup\u{2026}", processedEntities, nil)
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

    private func writeEnvelopeToDisk(
        _ envelope: BackupEnvelope, to url: URL, encoder: JSONEncoder
    ) throws {
        let envBytes = try encoder.encode(envelope)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                let name = url.lastPathComponent
                let desc = error.localizedDescription
                Self.logger.warning("Failed to remove file \(name, privacy: .public): \(desc, privacy: .public)")
            }
        }
        try envBytes.write(to: url, options: .atomic)
    }

    private func verifyBackupFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder.backupConfigured()
        _ = try decoder.decode(BackupEnvelope.self, from: data)
    }
}
// swiftlint:enable type_body_length
