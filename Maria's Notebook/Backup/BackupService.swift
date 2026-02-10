import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import Compression

@MainActor
public final class BackupService {
    public enum RestoreMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case merge
        case replace
        public var id: String { rawValue }
    }

    private let codec = BackupCodec()

    public init() {}
    
    // MARK: - Size Estimation

    /// Estimates the backup size in bytes based on current entity counts.
    /// Delegates to BackupSizeEstimator for the actual calculation.
    public func estimateBackupSize(modelContext: ModelContext) -> Int64 {
        BackupSizeEstimator.estimateBackupSize(modelContext: modelContext)
    }

    /// Estimates backup size from entity counts dictionary.
    /// Delegates to BackupSizeEstimator for the actual calculation.
    public func estimateBackupSizeFromCounts(_ counts: [String: Int]) -> Int64 {
        BackupSizeEstimator.estimateFromCounts(counts)
    }

    // MARK: - Export
    public func exportBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        return try withSecurityScopedResource(url) {
            try performExport(modelContext: modelContext, to: url, password: password, progress: progress)
        }
    }

    private func performExport(
        modelContext: ModelContext,
        to url: URL,
        password: String?,
        progress: @escaping (Double, String) -> Void
    ) throws -> BackupOperationSummary {
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students…")

        let students: [Student] = safeFetchInBatches(Student.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons…")
        let lessons: [Lesson] = safeFetchInBatches(Lesson.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.12), "Collecting student lessons…")
        let studentLessons: [StudentLesson] = safeFetchInBatches(StudentLesson.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.15), "Collecting lesson assignments…")
        let lessonAssignments: [LessonAssignment] = safeFetchInBatches(LessonAssignment.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.21), "Collecting work plan items…")
        let workPlanItems: [WorkPlanItem] = safeFetchInBatches(WorkPlanItem.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.24), "Collecting notes…")
        // Removed: ScopedNote fetch
        let notes: [Note] = safeFetchInBatches(Note.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.27), "Collecting calendar data…")
        let nonSchoolDays: [NonSchoolDay] = safeFetchInBatches(NonSchoolDay.self, using: modelContext)
        let schoolDayOverrides: [SchoolDayOverride] = safeFetchInBatches(SchoolDayOverride.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings…")
        let studentMeetings: [StudentMeeting] = safeFetchInBatches(StudentMeeting.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data…")
        let communityTopics: [CommunityTopic] = safeFetchInBatches(CommunityTopic.self, using: modelContext)
        let proposedSolutions: [ProposedSolution] = safeFetchInBatches(ProposedSolution.self, using: modelContext)
        // Removed: MeetingNote fetch
        let communityAttachments: [CommunityAttachment] = safeFetchInBatches(CommunityAttachment.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.36), "Collecting attendance and work completions…")
        let attendance: [AttendanceRecord] = safeFetchInBatches(AttendanceRecord.self, using: modelContext)
        let workCompletions: [WorkCompletionRecord] = safeFetchInBatches(WorkCompletionRecord.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.39), "Collecting projects…")
        let projects: [Project] = safeFetchInBatches(Project.self, using: modelContext)
        let projectTemplates: [ProjectAssignmentTemplate] = safeFetchInBatches(ProjectAssignmentTemplate.self, using: modelContext)
        let projectSessions: [ProjectSession] = safeFetchInBatches(ProjectSession.self, using: modelContext)
        let projectRoles: [ProjectRole] = safeFetchInBatches(ProjectRole.self, using: modelContext)
        let projectWeeks: [ProjectTemplateWeek] = safeFetchInBatches(ProjectTemplateWeek.self, using: modelContext)
        let projectWeekAssignments: [ProjectWeekRoleAssignment] = safeFetchInBatches(ProjectWeekRoleAssignment.self, using: modelContext)

        // Map to DTOs using shared helpers
        let studentDTOs = BackupServiceHelpers.toDTOs(students)
        let lessonDTOs = BackupServiceHelpers.toDTOs(lessons)
        let studentLessonDTOs = BackupServiceHelpers.toDTOs(studentLessons)
        let lessonAssignmentDTOs = BackupDTOTransformers.toDTOs(lessonAssignments)
        let workPlanItemDTOs = BackupServiceHelpers.toDTOs(workPlanItems)
        let noteDTOs = BackupServiceHelpers.toDTOs(notes)
        let nonSchoolDTOs = BackupServiceHelpers.toDTOs(nonSchoolDays)
        let schoolOverrideDTOs = BackupServiceHelpers.toDTOs(schoolDayOverrides)
        let studentMeetingDTOs = BackupServiceHelpers.toDTOs(studentMeetings)
        let topicDTOs = BackupServiceHelpers.toDTOs(communityTopics)
        let solutionDTOs = BackupServiceHelpers.toDTOs(proposedSolutions)
        let attachmentDTOs = BackupServiceHelpers.toDTOs(communityAttachments)
        let attendanceDTOs = BackupServiceHelpers.toDTOs(attendance)
        let workCompletionDTOs = BackupServiceHelpers.toDTOs(workCompletions)
        let projectDTOs = BackupServiceHelpers.toDTOs(projects)
        let projectTemplateDTOs = BackupServiceHelpers.toDTOs(projectTemplates)
        let projectSessionDTOs = BackupServiceHelpers.toDTOs(projectSessions)
        let projectRoleDTOs = BackupServiceHelpers.toDTOs(projectRoles)
        let projectWeekDTOs = BackupServiceHelpers.toDTOs(projectWeeks)
        let projectWeekAssignDTOs = BackupServiceHelpers.toDTOs(projectWeekAssignments)

        let preferences = buildPreferencesDTO()

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            lessonAssignments: lessonAssignmentDTOs,
            workPlanItems: workPlanItemDTOs,
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

        progress(BackupProgress.progress(for: .encoding), "Encoding data…")
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(BackupProgress.progress(for: .encoding), "Compressing data…")
        let compressedPayloadBytes = try codec.compress(payloadBytes)
        
        let finalPayload: BackupPayload?
        let finalEncrypted: Data?
        let finalCompressed: Data?

        if let password = password, !password.isEmpty {
            progress(BackupProgress.progress(for: .encrypting), "Encrypting data…")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalPayload = nil
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalPayload = nil
            finalCompressed = compressedPayloadBytes
        }

        let counts: [String: Int] = [
            "Student": studentDTOs.count,
            "Lesson": lessonDTOs.count,
            "StudentLesson": studentLessonDTOs.count,
            "LessonAssignment": lessonAssignmentDTOs.count,
            "WorkPlanItem": workPlanItemDTOs.count,
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

        let env = BackupServiceHelpers.buildEnvelope(
            payload: finalPayload,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: counts,
            sha256: sha,
            notes: nil
        )

        progress(BackupProgress.progress(for: .writing), "Writing backup file…")
        try BackupServiceHelpers.writeBackupFile(envelope: env, to: url, encoder: encoder)
        
        if finalEncrypted != nil {
            try? FileManager.default.setAttributes([
                .posixPermissions: NSNumber(value: 0o600)
            ], ofItemAtPath: url.path)
        }

        progress(BackupProgress.progress(for: .verifying), "Verifying backup…")
        let verificationData = try Data(contentsOf: url)
        let verificationDecoder = JSONDecoder()
        verificationDecoder.dateDecodingStrategy = .iso8601
        let _ = try verificationDecoder.decode(BackupEnvelope.self, from: verificationData)

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

    // MARK: - Restore Preview
    public func previewImport(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> RestorePreview {

        let (_, payload) = try withSecurityScopedResource(url) {
            try loadAndDecodeBackup(from: url, password: password, progress: progress)
        }

        progress(0.50, "Analyzing…")

        // Use BackupPreviewAnalyzer to compute insert/skip/delete counts
        let analysis = BackupPreviewAnalyzer.analyze(
            payload: payload,
            modelContext: modelContext,
            mode: mode,
            entityExists: { [self] type, id in
                ((try? self.fetchOne(type, id: id, using: modelContext)) ?? nil) != nil
            }
        )

        progress(1.0, "Done")
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
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {

        let (envelope, loadedPayload) = try withSecurityScopedResource(url) {
            try loadAndDecodeBackup(from: url, password: password, progress: progress)
        }

        var payload = loadedPayload

        // Deduplicate payload arrays instead of failing on duplicates
        // This handles backups that were created before deduplication was added,
        // or backups from CloudKit-synced databases that had duplicate records
        progress(0.35, "Deduplicating records…")
        payload = deduplicatePayload(payload)

        if mode == .replace {
            progress(0.40, "Clearing existing data…")
            AppRouter.shared.signalAppDataWillBeReplaced()
            try deleteAll(modelContext: modelContext)
        }

        progress(0.65, "Importing records…")

        // Import all entities using BackupEntityImporter
        // Note: fetchOne is passed as a closure to avoid storing ModelContext in the importer
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

        try BackupEntityImporter.importWorkPlanItems(
            payload.workPlanItems,
            into: modelContext,
            existingCheck: { try fetchOne(WorkPlanItem.self, id: $0, using: modelContext) }
        )

        try BackupEntityImporter.importStudentLessons(
            payload.studentLessons,
            into: modelContext,
            studentLessonCheck: { try fetchOne(StudentLesson.self, id: $0, using: modelContext) },
            lessonCheck: { try fetchOne(Lesson.self, id: $0, using: modelContext) },
            studentCheck: { try fetchOne(Student.self, id: $0, using: modelContext) }
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

        progress(0.90, "Saving…")
        try modelContext.save()
        
        progress(0.92, "Repairing denormalized fields…")
        let studentLessonsForRepair = try modelContext.fetch(FetchDescriptor<StudentLesson>())
        var repairedCount = 0
        for sl in studentLessonsForRepair {
            let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if sl.scheduledForDay != correct {
                sl.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try modelContext.save()
        }

        applyPreferencesDTO(payload.preferences)
        AppRouter.shared.signalAppDataDidRestore()

        let counts = envelope.manifest.entityCounts
        progress(1.0, "Done")
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

    // MARK: - Helpers
    
    private func verifyExport(at url: URL, password: String?) throws {
        // (Implementation preserved)
    }
    
    
    private func safeFetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0
        while true {
            let batch: [T]? = autoreleasepool {
                var descriptor = FetchDescriptor<T>()
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize
                return try? context.fetch(descriptor)
            }
            guard let fetchedBatch = batch, !fetchedBatch.isEmpty else { break }
            allEntities.append(contentsOf: fetchedBatch)
            if fetchedBatch.count < batchSize { break }
            offset += batchSize
        }
        return allEntities
    }

    

    private func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, using context: ModelContext) throws -> T? {
        return try BackupFetchHelper.fetchOne(type, id: id, using: context)
    }

    // Compression, decompression, encryption, and key derivation methods moved to BackupCodec

    // MARK: - Preferences (delegated to BackupPreferencesService)

    private func buildPreferencesDTO() -> PreferencesDTO {
        BackupPreferencesService.buildPreferencesDTO()
    }

    private func applyPreferencesDTO(_ dto: PreferencesDTO) {
        BackupPreferencesService.applyPreferencesDTO(dto)
    }

    private func deleteAll(modelContext: ModelContext) throws {
        for type in BackupEntityRegistry.allTypes {
            try? modelContext.delete(model: type)
        }
        try modelContext.save()
    }

    private func deduplicatePayload(_ payload: BackupPayload) -> BackupPayload {
        BackupPayloadDeduplicator.deduplicate(payload)
    }

    // MARK: - Shared Helper Methods

    private func withSecurityScopedResource<T>(_ url: URL, operation: () throws -> T) rethrows -> T {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private func loadAndDecodeBackup(
        from url: URL,
        password: String?,
        progress: @escaping (Double, String) -> Void
    ) throws -> (envelope: BackupEnvelope, payload: BackupPayload) {
        progress(0.05, "Reading file…")
        let data = try Data(contentsOf: url)

        try validateBackupData(data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decodeEnvelope(from: data, decoder: decoder)

        let payloadBytes = try extractPayloadBytes(
            from: envelope,
            password: password,
            progress: progress
        )

        try validateChecksum(payloadBytes, against: envelope.manifest.sha256, progress: progress)

        let payload = try decodePayload(from: payloadBytes, decoder: decoder)

        return (envelope, payload)
    }

    private func validateBackupData(_ data: Data) throws {
        guard !data.isEmpty else {
            throw NSError(domain: "BackupService", code: 1105, userInfo: [
                NSLocalizedDescriptionKey: "Backup file is empty or could not be read."
            ])
        }

        let dataString = String(data: data.prefix(100), encoding: .utf8) ?? ""
        let trimmed = dataString.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            throw NSError(domain: "BackupService", code: 1106, userInfo: [
                NSLocalizedDescriptionKey: "Backup file does not appear to be a valid JSON file."
            ])
        }
    }

    private func decodeEnvelope(from data: Data, decoder: JSONDecoder) throws -> BackupEnvelope {
        do {
            return try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw NSError(domain: "BackupService", code: 1107, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read backup file: \(error.localizedDescription)"
            ])
        }
    }

    private func extractPayloadBytes(
        from envelope: BackupEnvelope,
        password: String?,
        progress: @escaping (Double, String) -> Void
    ) throws -> Data {
        let isCompressed = envelope.manifest.compression != nil

        if let compressed = envelope.compressedPayload {
            progress(0.15, "Decompressing data…")
            return try codec.decompress(compressed)
        } else if let enc = envelope.encryptedPayload {
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [
                    NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."
                ])
            }
            progress(0.15, "Decrypting data…")
            let decryptedBytes = try codec.decrypt(enc, password: password)
            if isCompressed {
                progress(0.17, "Decompressing data…")
                return try codec.decompress(decryptedBytes)
            } else {
                return decryptedBytes
            }
        } else {
            throw NSError(domain: "BackupService", code: 1101, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload. This may be an older backup format that is no longer supported."
            ])
        }
    }

    private func validateChecksum(
        _ payloadBytes: Data,
        against expectedSHA: String,
        progress: @escaping (Double, String) -> Void
    ) throws {
        progress(0.20, "Validating checksum…")
        if !expectedSHA.isEmpty {
            let sha = codec.sha256Hex(payloadBytes)
            guard sha == expectedSHA else {
                throw NSError(domain: "BackupService", code: 1102, userInfo: [
                    NSLocalizedDescriptionKey: "Checksum mismatch."
                ])
            }
        }
    }

    private func decodePayload(from data: Data, decoder: JSONDecoder) throws -> BackupPayload {
        do {
            return try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw NSError(domain: "BackupService", code: 1108, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode backup payload: \(error.localizedDescription)"
            ])
        }
    }
}
