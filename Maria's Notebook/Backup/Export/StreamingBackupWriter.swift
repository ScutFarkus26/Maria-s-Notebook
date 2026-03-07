import Foundation
import SwiftData

/// Mutable collector for streaming export to avoid `inout` across `async` boundaries
@MainActor
private final class StreamCollector {
    var payload: BackupPayload
    var processedEntities = 0

    init(preferences: PreferencesDTO) {
        payload = BackupPayload(
            items: [], students: [], lessons: [],
            legacyPresentations: [], lessonAssignments: [],
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
    public func streamingExport(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws -> BackupOperationSummary {

        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.0, "Initializing streaming export\u{2026}", 0, nil)

        let counts = try await collectEntityCounts(modelContext: modelContext)
        let totalEntities = counts.values.reduce(0, +)
        progress(0.05, "Processing \(totalEntities) entities in batches\u{2026}", totalEntities, nil)

        let collector = StreamCollector(preferences: buildPreferencesDTO())
        try await streamCoreEntities(into: collector, from: modelContext, progress: progress)
        try await streamRelationEntities(into: collector, from: modelContext, progress: progress)
        try await streamV8Entities(into: collector, from: modelContext, progress: progress)
        try await streamExtraEntities(into: collector, from: modelContext, progress: progress)

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
        from modelContext: ModelContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        let s = try await streamFetch(Student.self, from: modelContext, progress: { count, type in
            collector.processedEntities += count
            progress(0.10, "Processing students\u{2026}", collector.processedEntities, type)
        })
        let l = try await streamFetch(Lesson.self, from: modelContext, progress: { count, type in
            collector.processedEntities += count
            progress(0.20, "Processing lessons\u{2026}", collector.processedEntities, type)
        })
        let n = try await streamFetch(Note.self, from: modelContext, progress: { count, type in
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
        from modelContext: ModelContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.35, "Processing remaining entities\u{2026}", collector.processedEntities, nil)

        // LegacyPresentation removed — no longer exported in new backups

        let lessonAssignments: [LessonAssignment] = try await streamFetchRaw(LessonAssignment.self, from: modelContext)
        collector.payload.lessonAssignments = BackupDTOTransformers.toDTOs(lessonAssignments)

        let nonSchoolDays: [NonSchoolDay] = try await streamFetchRaw(NonSchoolDay.self, from: modelContext)
        collector.payload.nonSchoolDays = BackupDTOTransformers.toDTOs(nonSchoolDays)

        let schoolDayOverrides: [SchoolDayOverride] =
            try await streamFetchRaw(SchoolDayOverride.self, from: modelContext)
        collector.payload.schoolDayOverrides = BackupDTOTransformers.toDTOs(schoolDayOverrides)

        let studentMeetings: [StudentMeeting] = try await streamFetchRaw(StudentMeeting.self, from: modelContext)
        collector.payload.studentMeetings = BackupDTOTransformers.toDTOs(studentMeetings)

        let communityTopics: [CommunityTopic] = try await streamFetchRaw(CommunityTopic.self, from: modelContext)
        collector.payload.communityTopics = BackupDTOTransformers.toDTOs(communityTopics)

        let proposedSolutions: [ProposedSolution] = try await streamFetchRaw(ProposedSolution.self, from: modelContext)
        collector.payload.proposedSolutions = BackupDTOTransformers.toDTOs(proposedSolutions)

        let communityAttachments: [CommunityAttachment] = try await streamFetchRaw(
            CommunityAttachment.self, from: modelContext
        )
        collector.payload.communityAttachments = BackupDTOTransformers.toDTOs(communityAttachments)

        let attendance: [AttendanceRecord] = try await streamFetchRaw(AttendanceRecord.self, from: modelContext)
        collector.payload.attendance = BackupDTOTransformers.toDTOs(attendance)

        let workCompletions: [WorkCompletionRecord] = try await streamFetchRaw(
            WorkCompletionRecord.self, from: modelContext
        )
        collector.payload.workCompletions = BackupDTOTransformers.toDTOs(workCompletions)

        let projects: [Project] = try await streamFetchRaw(Project.self, from: modelContext)
        collector.payload.projects = BackupDTOTransformers.toDTOs(projects)

        let projectTemplates: [ProjectAssignmentTemplate] = try await streamFetchRaw(
            ProjectAssignmentTemplate.self, from: modelContext
        )
        collector.payload.projectAssignmentTemplates = BackupDTOTransformers.toDTOs(projectTemplates)

        let projectSessions: [ProjectSession] = try await streamFetchRaw(ProjectSession.self, from: modelContext)
        collector.payload.projectSessions = BackupDTOTransformers.toDTOs(projectSessions)

        let projectRoles: [ProjectRole] = try await streamFetchRaw(ProjectRole.self, from: modelContext)
        collector.payload.projectRoles = BackupDTOTransformers.toDTOs(projectRoles)

        let projectWeeks: [ProjectTemplateWeek] = try await streamFetchRaw(ProjectTemplateWeek.self, from: modelContext)
        collector.payload.projectTemplateWeeks = BackupDTOTransformers.toDTOs(projectWeeks)

        let projectWeekAssignments: [ProjectWeekRoleAssignment] = try await streamFetchRaw(
            ProjectWeekRoleAssignment.self, from: modelContext
        )
        collector.payload.projectWeekRoleAssignments = BackupDTOTransformers.toDTOs(projectWeekAssignments)
    }

    private func streamV8Entities(
        into collector: StreamCollector,
        from modelContext: ModelContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.40, "Processing work tracking\u{2026}", collector.processedEntities, nil)

        let workCheckIns: [WorkCheckIn] = try await streamFetchRaw(WorkCheckIn.self, from: modelContext)
        collector.payload.workCheckIns = BackupDTOTransformers.toDTOs(workCheckIns)

        let workSteps: [WorkStep] = try await streamFetchRaw(WorkStep.self, from: modelContext)
        collector.payload.workSteps = BackupDTOTransformers.toDTOs(workSteps)

        let workParticipants: [WorkParticipantEntity] = try await streamFetchRaw(
            WorkParticipantEntity.self, from: modelContext
        )
        collector.payload.workParticipants = BackupDTOTransformers.toDTOs(workParticipants)

        let practiceSessions: [PracticeSession] = try await streamFetchRaw(PracticeSession.self, from: modelContext)
        collector.payload.practiceSessions = BackupDTOTransformers.toDTOs(practiceSessions)

        progress(0.44, "Processing lesson extras\u{2026}", collector.processedEntities, nil)

        let lessonAttachments: [LessonAttachment] = try await streamFetchRaw(LessonAttachment.self, from: modelContext)
        collector.payload.lessonAttachments = BackupDTOTransformers.toDTOs(lessonAttachments)

        let lessonPresentations: [LessonPresentation] = try await streamFetchRaw(
            LessonPresentation.self, from: modelContext
        )
        collector.payload.lessonPresentations = BackupDTOTransformers.toDTOs(lessonPresentations)

        let sampleWorks: [SampleWork] = try await streamFetchRaw(SampleWork.self, from: modelContext)
        collector.payload.sampleWorks = BackupDTOTransformers.toDTOs(sampleWorks)

        let sampleWorkSteps: [SampleWorkStep] = try await streamFetchRaw(SampleWorkStep.self, from: modelContext)
        collector.payload.sampleWorkSteps = BackupDTOTransformers.toDTOs(sampleWorkSteps)
    }

    private func streamExtraEntities(
        into collector: StreamCollector,
        from modelContext: ModelContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.46, "Processing templates\u{2026}", collector.processedEntities, nil)

        let noteTemplates: [NoteTemplate] = try await streamFetchRaw(NoteTemplate.self, from: modelContext)
        collector.payload.noteTemplates = BackupDTOTransformers.toDTOs(noteTemplates)

        let meetingTemplates: [MeetingTemplate] = try await streamFetchRaw(MeetingTemplate.self, from: modelContext)
        collector.payload.meetingTemplates = BackupDTOTransformers.toDTOs(meetingTemplates)

        progress(0.48, "Processing reminders & calendar\u{2026}", collector.processedEntities, nil)

        let reminders: [Reminder] = try await streamFetchRaw(Reminder.self, from: modelContext)
        collector.payload.reminders = BackupDTOTransformers.toDTOs(reminders)

        let calendarEvents: [CalendarEvent] = try await streamFetchRaw(CalendarEvent.self, from: modelContext)
        collector.payload.calendarEvents = BackupDTOTransformers.toDTOs(calendarEvents)

        progress(0.50, "Processing tracks\u{2026}", collector.processedEntities, nil)

        let tracks: [Track] = try await streamFetchRaw(Track.self, from: modelContext)
        collector.payload.tracks = BackupDTOTransformers.toDTOs(tracks)

        let trackSteps: [TrackStep] = try await streamFetchRaw(TrackStep.self, from: modelContext)
        collector.payload.trackSteps = BackupDTOTransformers.toDTOs(trackSteps)

        let enrollments: [StudentTrackEnrollment] = try await streamFetchRaw(
            StudentTrackEnrollment.self, from: modelContext
        )
        collector.payload.studentTrackEnrollments = BackupDTOTransformers.toDTOs(enrollments)

        let groupTracks: [GroupTrack] = try await streamFetchRaw(GroupTrack.self, from: modelContext)
        collector.payload.groupTracks = BackupDTOTransformers.toDTOs(groupTracks)

        progress(0.52, "Processing documents & supplies\u{2026}", collector.processedEntities, nil)

        let documents: [Document] = try await streamFetchRaw(Document.self, from: modelContext)
        collector.payload.documents = BackupDTOTransformers.toDTOs(documents)

        let supplies: [Supply] = try await streamFetchRaw(Supply.self, from: modelContext)
        collector.payload.supplies = BackupDTOTransformers.toDTOs(supplies)

        let supplyTransactions: [SupplyTransaction] = try await streamFetchRaw(
            SupplyTransaction.self, from: modelContext
        )
        collector.payload.supplyTransactions = BackupDTOTransformers.toDTOs(supplyTransactions)

        let procedures: [Procedure] = try await streamFetchRaw(Procedure.self, from: modelContext)
        collector.payload.procedures = BackupDTOTransformers.toDTOs(procedures)

        progress(0.54, "Processing schedules\u{2026}", collector.processedEntities, nil)

        let schedules: [Schedule] = try await streamFetchRaw(Schedule.self, from: modelContext)
        collector.payload.schedules = BackupDTOTransformers.toDTOs(schedules)

        let scheduleSlots: [ScheduleSlot] = try await streamFetchRaw(ScheduleSlot.self, from: modelContext)
        collector.payload.scheduleSlots = BackupDTOTransformers.toDTOs(scheduleSlots)

        progress(0.56, "Processing issues\u{2026}", collector.processedEntities, nil)

        let issues: [Issue] = try await streamFetchRaw(Issue.self, from: modelContext)
        collector.payload.issues = BackupDTOTransformers.toDTOs(issues)

        let issueActions: [IssueAction] = try await streamFetchRaw(IssueAction.self, from: modelContext)
        collector.payload.issueActions = BackupDTOTransformers.toDTOs(issueActions)

        try await streamSnapshotAndTodoDTOs(into: collector, from: modelContext, progress: progress)
    }

    private func streamSnapshotAndTodoDTOs(
        into collector: StreamCollector,
        from modelContext: ModelContext,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws {
        progress(0.57, "Processing snapshots & todos\u{2026}", collector.processedEntities, nil)

        let snapshots: [DevelopmentSnapshot] = try await streamFetchRaw(DevelopmentSnapshot.self, from: modelContext)
        collector.payload.developmentSnapshots = BackupDTOTransformers.toDTOs(snapshots)

        let todoItems: [TodoItem] = try await streamFetchRaw(TodoItem.self, from: modelContext)
        collector.payload.todoItems = BackupDTOTransformers.toDTOs(todoItems)

        let todoSubtasks: [TodoSubtask] = try await streamFetchRaw(TodoSubtask.self, from: modelContext)
        collector.payload.todoSubtasks = BackupDTOTransformers.toDTOs(todoSubtasks)

        let todoTemplates: [TodoTemplate] = try await streamFetchRaw(TodoTemplate.self, from: modelContext)
        collector.payload.todoTemplates = BackupDTOTransformers.toDTOs(todoTemplates)

        let agendaOrders: [TodayAgendaOrder] = try await streamFetchRaw(TodayAgendaOrder.self, from: modelContext)
        collector.payload.todayAgendaOrders = BackupDTOTransformers.toDTOs(agendaOrders)
    }

    // MARK: - Finalization

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
        if let password = password, !password.isEmpty {
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
                print("\u{26a0}\u{fe0f} [Backup:streamingExport] Failed to remove existing file" +
                      " at \(url.lastPathComponent): \(error)")
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
