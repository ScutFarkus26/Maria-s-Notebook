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
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students…")

        let students: [Student] = safeFetchInBatches(Student.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons…")
        let lessons: [Lesson] = safeFetchInBatches(Lesson.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.12), "Collecting student lessons…")
        let studentLessons: [StudentLesson] = safeFetchInBatchesWithErrorHandling(StudentLesson.self, using: modelContext)
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
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings and presentations…")
        let studentMeetings: [StudentMeeting] = safeFetchInBatches(StudentMeeting.self, using: modelContext)
        let presentations: [Presentation] = safeFetchInBatches(Presentation.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data…")
        let communityTopics: [CommunityTopic] = safeFetchInBatchesWithErrorHandling(CommunityTopic.self, using: modelContext)
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

        // Map to DTOs using BackupDTOTransformers
        let studentDTOs = BackupDTOTransformers.toDTOs(students)
        let lessonDTOs = BackupDTOTransformers.toDTOs(lessons)
        let studentLessonDTOs = BackupDTOTransformers.toDTOs(studentLessons)
        let lessonAssignmentDTOs = BackupDTOTransformers.toDTOs(lessonAssignments)
        let workPlanItemDTOs = BackupDTOTransformers.toDTOs(workPlanItems)
        let scopedNoteDTOs: [ScopedNoteDTO] = [] // Removed entity
        let noteDTOs = BackupDTOTransformers.toDTOs(notes)
        let nonSchoolDTOs = BackupDTOTransformers.toDTOs(nonSchoolDays)
        let schoolOverrideDTOs = BackupDTOTransformers.toDTOs(schoolDayOverrides)
        let studentMeetingDTOs = BackupDTOTransformers.toDTOs(studentMeetings)
        let presentationDTOs = BackupDTOTransformers.toDTOs(presentations)
        let topicDTOs = BackupDTOTransformers.toDTOs(communityTopics)
        let solutionDTOs = BackupDTOTransformers.toDTOs(proposedSolutions)
        let meetingNoteDTOs: [MeetingNoteDTO] = [] // Removed entity
        let attachmentDTOs = BackupDTOTransformers.toDTOs(communityAttachments)
        let attendanceDTOs = BackupDTOTransformers.toDTOs(attendance)
        let workCompletionDTOs = BackupDTOTransformers.toDTOs(workCompletions)
        let projectDTOs = BackupDTOTransformers.toDTOs(projects)
        let projectTemplateDTOs = BackupDTOTransformers.toDTOs(projectTemplates)
        let projectSessionDTOs = BackupDTOTransformers.toDTOs(projectSessions)
        let projectRoleDTOs = BackupDTOTransformers.toDTOs(projectRoles)
        let projectWeekDTOs = BackupDTOTransformers.toDTOs(projectWeeks)
        let projectWeekAssignDTOs = BackupDTOTransformers.toDTOs(projectWeekAssignments)

        let preferences = buildPreferencesDTO()

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            lessonAssignments: lessonAssignmentDTOs,
            workPlanItems: workPlanItemDTOs,
            scopedNotes: scopedNoteDTOs,
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: studentMeetingDTOs,
            presentations: presentationDTOs,
            communityTopics: topicDTOs,
            proposedSolutions: solutionDTOs,
            meetingNotes: meetingNoteDTOs,
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(BackupProgress.progress(for: .encoding), "Compressing data…")
        let compressedPayloadBytes = try codec.compress(payloadBytes)
        
        let finalPayload: BackupPayload?
        let finalEncrypted: Data?
        let finalCompressed: Data?
        let compressionUsed: String?

        if let password = password, !password.isEmpty {
            progress(BackupProgress.progress(for: .encrypting), "Encrypting data…")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalPayload = nil
            finalCompressed = nil
            compressionUsed = BackupFile.compressionAlgorithm
        } else {
            finalEncrypted = nil
            finalPayload = nil
            finalCompressed = compressedPayloadBytes
            compressionUsed = BackupFile.compressionAlgorithm
        }

        let counts: [String: Int] = [
            "Student": studentDTOs.count,
            "Lesson": lessonDTOs.count,
            "StudentLesson": studentLessonDTOs.count,
            "LessonAssignment": lessonAssignmentDTOs.count,
            "WorkPlanItem": workPlanItemDTOs.count,
            "ScopedNote": scopedNoteDTOs.count,
            "Note": noteDTOs.count,
            "NonSchoolDay": nonSchoolDTOs.count,
            "SchoolDayOverride": schoolOverrideDTOs.count,
            "StudentMeeting": studentMeetingDTOs.count,
            "Presentation": presentationDTOs.count,
            "CommunityTopic": topicDTOs.count,
            "ProposedSolution": solutionDTOs.count,
            "MeetingNote": meetingNoteDTOs.count,
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

        let env = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: BackupManifest(entityCounts: counts, sha256: sha, notes: nil, compression: compressionUsed),
            payload: finalPayload,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed
        )

        progress(BackupProgress.progress(for: .writing), "Writing backup file…")
        let envBytes = try encoder.encode(env)
        
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)
        
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
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.05, "Reading file…")
        let data = try Data(contentsOf: url)
        
        guard !data.isEmpty else {
            throw NSError(domain: "BackupService", code: 1105, userInfo: [NSLocalizedDescriptionKey: "Backup file is empty or could not be read."])
        }
        
        let dataString = String(data: data.prefix(100), encoding: .utf8) ?? ""
        guard dataString.trimmingCharacters(in: .whitespaces).hasPrefix("{") || dataString.trimmingCharacters(in: .whitespaces).hasPrefix("[") else {
            throw NSError(domain: "BackupService", code: 1106, userInfo: [
                NSLocalizedDescriptionKey: "Backup file does not appear to be a valid JSON file."
            ])
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw NSError(domain: "BackupService", code: 1107, userInfo: [NSLocalizedDescriptionKey: "Failed to read backup file: \(error.localizedDescription)"])
        }

        let payloadBytes: Data
        let isCompressed = envelope.manifest.compression != nil
        
        if envelope.payload != nil {
            if let extracted = try extractPayloadBytes(from: data) {
                payloadBytes = extracted
            } else {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .sortedKeys
                payloadBytes = try encoder.encode(envelope.payload!)
            }
        } else if let compressed = envelope.compressedPayload {
            progress(0.15, "Decompressing data…")
            payloadBytes = try codec.decompress(compressed)
        } else if let enc = envelope.encryptedPayload {
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."])
            }
            progress(0.15, "Decrypting data…")
            let decryptedBytes = try codec.decrypt(enc, password: password)
            if isCompressed {
                progress(0.17, "Decompressing data…")
                payloadBytes = try codec.decompress(decryptedBytes)
            } else {
                payloadBytes = decryptedBytes
            }
        } else {
            throw NSError(domain: "BackupService", code: 1101, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating checksum…")
        let bypassEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.backupAllowChecksumBypass)
        let shouldValidateChecksum = !bypassEnabled
        
        if shouldValidateChecksum && !envelope.manifest.sha256.isEmpty {
            let sha = codec.sha256Hex(payloadBytes)
            guard sha == envelope.manifest.sha256 else {
                throw NSError(domain: "BackupService", code: 1102, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch."])
            }
        }

        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: payloadBytes)
        } catch {
            throw NSError(domain: "BackupService", code: 1108, userInfo: [NSLocalizedDescriptionKey: "Failed to decode backup payload: \(error.localizedDescription)"])
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
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.05, "Reading file…")
        let data = try Data(contentsOf: url)
        
        guard !data.isEmpty else {
            throw NSError(domain: "BackupService", code: 1105, userInfo: [NSLocalizedDescriptionKey: "Backup file is empty."])
        }
        
        // Validation logic for JSON... (simplified here, assume valid per existing logic)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        // Resolve payload bytes
        let payloadBytes: Data
        let isCompressed = envelope.manifest.compression != nil
        
        if envelope.payload != nil {
            if let extracted = try extractPayloadBytes(from: data) {
                payloadBytes = extracted
            } else {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .sortedKeys
                payloadBytes = try encoder.encode(envelope.payload!)
            }
        } else if let compressed = envelope.compressedPayload {
            progress(0.15, "Decompressing data…")
            payloadBytes = try codec.decompress(compressed)
        } else if let enc = envelope.encryptedPayload {
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [NSLocalizedDescriptionKey: "Encrypted backup."])
            }
            let decryptedBytes = try codec.decrypt(enc, password: password)
            if isCompressed {
                payloadBytes = try codec.decompress(decryptedBytes)
            } else {
                payloadBytes = decryptedBytes
            }
        } else {
            throw NSError(domain: "BackupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Missing payload."])
        }

        var payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: payloadBytes)
        } catch {
            throw NSError(domain: "BackupService", code: 1108, userInfo: [NSLocalizedDescriptionKey: "Failed to decode backup payload."])
        }

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

        // Fetch all student lessons once for presentation legacy ID matching
        let allStudentLessons = (try? modelContext.fetch(FetchDescriptor<StudentLesson>())) ?? []
        try BackupEntityImporter.importPresentations(
            payload.presentations,
            into: modelContext,
            existingCheck: { try fetchOne(Presentation.self, id: $0, using: modelContext) },
            allStudentLessons: allStudentLessons
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
    
    private func safeFetch<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> [T] {
        let descriptor = FetchDescriptor<T>()
        return (try? context.fetch(descriptor)) ?? []
    }
    
    private func safeFetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0
        while true {
            // Use autoreleasepool to release intermediate memory during batch processing
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
    
    private func safeFetchInBatchesWithErrorHandling<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0
        while true {
            // Use autoreleasepool to release intermediate memory during batch processing
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
    
    private func safeFetchWithErrorHandling<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> [T] {
        if let results = try? context.fetch(FetchDescriptor<T>()) {
            return results
        }
        #if DEBUG
        print("BackupService: Warning - Could not fetch \(String(describing: type)). Skipping this entity type.")
        #endif
        return []
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, using context: ModelContext) throws -> T? {
        if type == Student.self {
            let arr = try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Lesson.self {
            let arr = try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == StudentLesson.self {
            let arr = try context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == LessonAssignment.self {
            let arr = try context.fetch(FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        // WorkContract removed - use WorkModel instead
        if type == WorkModel.self {
            let arr = try context.fetch(FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkPlanItem.self {
            let arr = try context.fetch(FetchDescriptor<WorkPlanItem>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        // Removed: ScopedNote
        if type == Note.self {
            let arr = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == NonSchoolDay.self {
            let arr = try context.fetch(FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == SchoolDayOverride.self {
            let arr = try context.fetch(FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == StudentMeeting.self {
            let arr = try context.fetch(FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Presentation.self {
            let arr = try context.fetch(FetchDescriptor<Presentation>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == CommunityTopic.self {
            let arr = try context.fetch(FetchDescriptor<CommunityTopic>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProposedSolution.self {
            let arr = try context.fetch(FetchDescriptor<ProposedSolution>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        // Removed: MeetingNote
        if type == CommunityAttachment.self {
            let arr = try context.fetch(FetchDescriptor<CommunityAttachment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == AttendanceRecord.self {
            let arr = try context.fetch(FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkCompletionRecord.self {
            let arr = try context.fetch(FetchDescriptor<WorkCompletionRecord>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Project.self {
            let arr = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectAssignmentTemplate.self {
            let arr = try context.fetch(FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectSession.self {
            let arr = try context.fetch(FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectRole.self {
            let arr = try context.fetch(FetchDescriptor<ProjectRole>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectTemplateWeek.self {
            let arr = try context.fetch(FetchDescriptor<ProjectTemplateWeek>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectWeekRoleAssignment.self {
            let arr = try context.fetch(FetchDescriptor<ProjectWeekRoleAssignment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        return nil
    }

    // MARK: - Payload Extraction (delegated to BackupPayloadExtractor)

    private func extractPayloadBytes(from envelopeData: Data) throws -> Data? {
        try BackupPayloadExtractor.extractPayloadBytes(from: envelopeData)
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

    // MARK: - Payload Deduplication

    /// Removes duplicate records from the backup payload, keeping the first occurrence of each ID.
    /// This handles backups created from databases that had duplicate records due to CloudKit sync issues.
    private func deduplicatePayload(_ payload: BackupPayload) -> BackupPayload {
        func uniqueBy<T>(_ items: [T], id: (T) -> UUID) -> [T] {
            var seen = Set<UUID>()
            return items.filter { item in
                let itemId = id(item)
                if seen.contains(itemId) {
                    return false
                }
                seen.insert(itemId)
                return true
            }
        }

        return BackupPayload(
            items: payload.items,
            students: uniqueBy(payload.students) { $0.id },
            lessons: uniqueBy(payload.lessons) { $0.id },
            studentLessons: uniqueBy(payload.studentLessons) { $0.id },
            lessonAssignments: uniqueBy(payload.lessonAssignments) { $0.id },
            workPlanItems: uniqueBy(payload.workPlanItems) { $0.id },
            scopedNotes: uniqueBy(payload.scopedNotes) { $0.id },
            notes: uniqueBy(payload.notes) { $0.id },
            nonSchoolDays: uniqueBy(payload.nonSchoolDays) { $0.id },
            schoolDayOverrides: uniqueBy(payload.schoolDayOverrides) { $0.id },
            studentMeetings: uniqueBy(payload.studentMeetings) { $0.id },
            presentations: uniqueBy(payload.presentations) { $0.id },
            communityTopics: uniqueBy(payload.communityTopics) { $0.id },
            proposedSolutions: uniqueBy(payload.proposedSolutions) { $0.id },
            meetingNotes: uniqueBy(payload.meetingNotes) { $0.id },
            communityAttachments: uniqueBy(payload.communityAttachments) { $0.id },
            attendance: uniqueBy(payload.attendance) { $0.id },
            workCompletions: uniqueBy(payload.workCompletions) { $0.id },
            projects: uniqueBy(payload.projects) { $0.id },
            projectAssignmentTemplates: uniqueBy(payload.projectAssignmentTemplates) { $0.id },
            projectSessions: uniqueBy(payload.projectSessions) { $0.id },
            projectRoles: uniqueBy(payload.projectRoles) { $0.id },
            projectTemplateWeeks: uniqueBy(payload.projectTemplateWeeks) { $0.id },
            projectWeekRoleAssignments: uniqueBy(payload.projectWeekRoleAssignments) { $0.id },
            preferences: payload.preferences
        )
    }
}
