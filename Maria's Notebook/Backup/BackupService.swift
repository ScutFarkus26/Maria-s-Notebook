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
        
        // Modern approach: Fetch and transform to DTOs in batches to reduce peak memory usage
        // This avoids holding both full models and DTOs in memory simultaneously
        let studentDTOs = fetchAndTransformInBatches(Student.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons…")
        let lessonDTOs = fetchAndTransformInBatches(Lesson.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.12), "Collecting student lessons…")
        let studentLessonDTOs = fetchAndTransformInBatches(StudentLesson.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.15), "Collecting lesson assignments…")
        let lessonAssignmentDTOs = fetchAndTransformInBatches(LessonAssignment.self, using: modelContext) { BackupDTOTransformers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.24), "Collecting notes…")
        let noteDTOs = fetchAndTransformInBatches(Note.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.27), "Collecting calendar data…")
        let nonSchoolDTOs = fetchAndTransformInBatches(NonSchoolDay.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let schoolOverrideDTOs = fetchAndTransformInBatches(SchoolDayOverride.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings…")
        let studentMeetingDTOs = fetchAndTransformInBatches(StudentMeeting.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data…")
        let topicDTOs = fetchAndTransformInBatches(CommunityTopic.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let solutionDTOs = fetchAndTransformInBatches(ProposedSolution.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let attachmentDTOs = fetchAndTransformInBatches(CommunityAttachment.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.36), "Collecting attendance and work completions…")
        let attendanceDTOs = fetchAndTransformInBatches(AttendanceRecord.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let workCompletionDTOs = fetchAndTransformInBatches(WorkCompletionRecord.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.39), "Collecting projects…")
        let projectDTOs = fetchAndTransformInBatches(Project.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let projectTemplateDTOs = fetchAndTransformInBatches(ProjectAssignmentTemplate.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let projectSessionDTOs = fetchAndTransformInBatches(ProjectSession.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let projectRoleDTOs = fetchAndTransformInBatches(ProjectRole.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let projectWeekDTOs = fetchAndTransformInBatches(ProjectTemplateWeek.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }
        let projectWeekAssignDTOs = fetchAndTransformInBatches(ProjectWeekRoleAssignment.self, using: modelContext) { BackupServiceHelpers.toDTOs($0) }

        let preferences = buildPreferencesDTO()

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
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
            do {
                try FileManager.default.setAttributes([
                    .posixPermissions: NSNumber(value: 0o600)
                ], ofItemAtPath: url.path)
            } catch {
                print("⚠️ [Backup:exportBackup] Failed to set file permissions: \(error)")
            }
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
                do {
                    return (try self.fetchOne(type, id: id, using: modelContext)) != nil
                } catch {
                    print("⚠️ [BackupService] Failed to check entity existence for type \(String(describing: type)): \(error)")
                    return false
                }
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
        try await importBackup(
            modelContext: modelContext,
            from: url,
            mode: mode,
            password: password,
            appRouter: AppRouter.shared,
            progress: progress
        )
    }
    
    // Internal version that accepts AppRouter for dependency injection
    func importBackup(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        appRouter: AppRouter,
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
            appRouter.signalAppDataWillBeReplaced()
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
        appRouter.signalAppDataDidRestore()

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
    
    
    /// Modern batched fetch that processes entities in memory-efficient chunks.
    /// Uses FetchDescriptor with offset/limit instead of loading everything at once.
    /// The autoreleasepool ensures each batch is released before fetching the next.
    private func safeFetchInBatches<T: PersistentModel>(
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
                    print("⚠️ [Backup:safeFetchInBatches] Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
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
    private func fetchAndTransformInBatches<T: PersistentModel, DTO>(
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
                    print("⚠️ [Backup:collectBatch] Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
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
            do {
                try modelContext.delete(model: type)
            } catch {
                print("⚠️ [Backup:deleteAll] Failed to delete \(type): \(error)")
            }
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
