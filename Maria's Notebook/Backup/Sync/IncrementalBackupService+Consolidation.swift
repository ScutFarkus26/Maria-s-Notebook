import Foundation
import SwiftData

// MARK: - Chain Consolidation

extension IncrementalBackupService {

    /// Consolidates a chain of incremental backups into a single full backup.
    /// This reduces storage space and simplifies restore operations.
    ///
    /// - Parameters:
    ///   - backupURLs: Array of incremental backup URLs in chronological order (oldest first)
    ///   - outputURL: Destination URL for the consolidated backup
    ///   - password: Optional encryption password for the consolidated backup
    ///   - progress: Progress callback
    /// - Returns: Metadata about the consolidated backup
    public func consolidateIncrementalChain(
        backupURLs: [URL],
        to outputURL: URL,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> ConsolidationResult {
        guard !backupURLs.isEmpty else {
            throw NSError(domain: "IncrementalBackupService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No backups provided for consolidation"
            ])
        }

        progress(0.0, "Starting consolidation...")

        // Track merged entity counts
        var mergedStudents: [UUID: StudentDTO] = [:]
        var mergedLessons: [UUID: LessonDTO] = [:]
        var mergedLegacyPresentations: [UUID: LegacyPresentationDTO] = [:]
        var mergedLessonAssignments: [UUID: LessonAssignmentDTO] = [:]
        // Phase 6: WorkPlanItem removed from schema - migrated to WorkCheckIn
        var mergedNotes: [UUID: NoteDTO] = [:]
        var mergedNonSchoolDays: [UUID: NonSchoolDayDTO] = [:]
        var mergedSchoolDayOverrides: [UUID: SchoolDayOverrideDTO] = [:]
        var mergedStudentMeetings: [UUID: StudentMeetingDTO] = [:]
        var mergedCommunityTopics: [UUID: CommunityTopicDTO] = [:]
        var mergedProposedSolutions: [UUID: ProposedSolutionDTO] = [:]
        var mergedCommunityAttachments: [UUID: CommunityAttachmentDTO] = [:]
        var mergedAttendance: [UUID: AttendanceRecordDTO] = [:]
        var mergedWorkCompletions: [UUID: WorkCompletionRecordDTO] = [:]
        var mergedProjects: [UUID: ProjectDTO] = [:]
        var mergedProjectTemplates: [UUID: ProjectAssignmentTemplateDTO] = [:]
        var mergedProjectSessions: [UUID: ProjectSessionDTO] = [:]
        var mergedProjectRoles: [UUID: ProjectRoleDTO] = [:]
        var mergedProjectWeeks: [UUID: ProjectTemplateWeekDTO] = [:]
        var mergedProjectWeekAssignments: [UUID: ProjectWeekRoleAssignmentDTO] = [:]

        var latestPreferences: PreferencesDTO?
        var processedCount = 0
        let totalBackups = Double(backupURLs.count)

        // Process each backup in order (oldest first, newer overwrites older)
        for (index, url) in backupURLs.enumerated() {
            let progressBase = Double(index) / totalBackups * 0.8
            progress(progressBase, "Processing backup \(index + 1) of \(backupURLs.count)...")

            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let payload = try await extractPayload(from: url)

            // Merge entities (newer backups overwrite older)
            for dto in payload.students { mergedStudents[dto.id] = dto }
            for dto in payload.lessons { mergedLessons[dto.id] = dto }
            for dto in payload.legacyPresentations { mergedLegacyPresentations[dto.id] = dto }
            for dto in payload.lessonAssignments { mergedLessonAssignments[dto.id] = dto }
            // Phase 6: WorkPlanItem removed from schema - skip merging
            for dto in payload.notes { mergedNotes[dto.id] = dto }
            for dto in payload.nonSchoolDays { mergedNonSchoolDays[dto.id] = dto }
            for dto in payload.schoolDayOverrides { mergedSchoolDayOverrides[dto.id] = dto }
            for dto in payload.studentMeetings { mergedStudentMeetings[dto.id] = dto }
            for dto in payload.communityTopics { mergedCommunityTopics[dto.id] = dto }
            for dto in payload.proposedSolutions { mergedProposedSolutions[dto.id] = dto }
            for dto in payload.communityAttachments { mergedCommunityAttachments[dto.id] = dto }
            for dto in payload.attendance { mergedAttendance[dto.id] = dto }
            for dto in payload.workCompletions { mergedWorkCompletions[dto.id] = dto }
            for dto in payload.projects { mergedProjects[dto.id] = dto }
            for dto in payload.projectAssignmentTemplates { mergedProjectTemplates[dto.id] = dto }
            for dto in payload.projectSessions { mergedProjectSessions[dto.id] = dto }
            for dto in payload.projectRoles { mergedProjectRoles[dto.id] = dto }
            for dto in payload.projectTemplateWeeks { mergedProjectWeeks[dto.id] = dto }
            for dto in payload.projectWeekRoleAssignments { mergedProjectWeekAssignments[dto.id] = dto }

            latestPreferences = payload.preferences
            processedCount += 1
        }

        progress(0.8, "Creating consolidated backup...")

        // Build consolidated payload
        let consolidatedPayload = BackupPayload(
            items: [],
            students: Array(mergedStudents.values),
            lessons: Array(mergedLessons.values),
            legacyPresentations: Array(mergedLegacyPresentations.values),
            lessonAssignments: Array(mergedLessonAssignments.values),
            notes: Array(mergedNotes.values),
            nonSchoolDays: Array(mergedNonSchoolDays.values),
            schoolDayOverrides: Array(mergedSchoolDayOverrides.values),
            studentMeetings: Array(mergedStudentMeetings.values),
            communityTopics: Array(mergedCommunityTopics.values),
            proposedSolutions: Array(mergedProposedSolutions.values),
            communityAttachments: Array(mergedCommunityAttachments.values),
            attendance: Array(mergedAttendance.values),
            workCompletions: Array(mergedWorkCompletions.values),
            projects: Array(mergedProjects.values),
            projectAssignmentTemplates: Array(mergedProjectTemplates.values),
            projectSessions: Array(mergedProjectSessions.values),
            projectRoles: Array(mergedProjectRoles.values),
            projectTemplateWeeks: Array(mergedProjectWeeks.values),
            projectWeekRoleAssignments: Array(mergedProjectWeekAssignments.values),
            preferences: latestPreferences ?? PreferencesDTO(values: [:])
        )

        // Encode and write
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(consolidatedPayload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(0.85, "Compressing...")
        let compressedBytes = try codec.compress(payloadBytes)

        let finalEncrypted: Data?
        let finalCompressed: Data?

        if let password = password, !password.isEmpty {
            progress(0.9, "Encrypting...")
            finalEncrypted = try codec.encrypt(compressedBytes, password: password)
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalCompressed = compressedBytes
        }

        // Build entity counts
        let counts: [String: Int] = [
            "Student": mergedStudents.count,
            "Lesson": mergedLessons.count,
            "LegacyPresentation": mergedLegacyPresentations.count,
            "LessonAssignment": mergedLessonAssignments.count,
            "Note": mergedNotes.count,
            "NonSchoolDay": mergedNonSchoolDays.count,
            "SchoolDayOverride": mergedSchoolDayOverrides.count,
            "StudentMeeting": mergedStudentMeetings.count,
            "CommunityTopic": mergedCommunityTopics.count,
            "ProposedSolution": mergedProposedSolutions.count,
            "CommunityAttachment": mergedCommunityAttachments.count,
            "AttendanceRecord": mergedAttendance.count,
            "WorkCompletionRecord": mergedWorkCompletions.count,
            "Project": mergedProjects.count,
            "ProjectAssignmentTemplate": mergedProjectTemplates.count,
            "ProjectSession": mergedProjectSessions.count,
            "ProjectRole": mergedProjectRoles.count,
            "ProjectTemplateWeek": mergedProjectWeeks.count,
            "ProjectWeekRoleAssignment": mergedProjectWeekAssignments.count
        ]

        let envelope = BackupServiceHelpers.buildEnvelope(
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: counts,
            sha256: sha,
            notes: "Consolidated from \(backupURLs.count) incremental backups"
        )

        progress(0.95, "Writing consolidated backup...")
        try BackupServiceHelpers.writeBackupFile(envelope: envelope, to: outputURL, encoder: encoder)

        progress(1.0, "Consolidation complete")

        let totalEntities = counts.values.reduce(0, +)
        let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0

        return ConsolidationResult(
            outputURL: outputURL,
            consolidatedBackupCount: backupURLs.count,
            totalEntities: totalEntities,
            entityCounts: counts,
            fileSize: fileSize,
            isEncrypted: finalEncrypted != nil
        )
    }

    /// Result of backup chain consolidation
    public struct ConsolidationResult: Sendable {
        public let outputURL: URL
        public let consolidatedBackupCount: Int
        public let totalEntities: Int
        public let entityCounts: [String: Int]
        public let fileSize: Int64
        public let isEncrypted: Bool

        public var formattedFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: fileSize)
        }
    }

    /// Extracts payload from a backup file (supports encrypted and compressed)
    func extractPayload(from url: URL) async throws -> BackupPayload {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let payloadBytes: Data

        if let payload = envelope.payload {
            let encoder = JSONEncoder.backupConfigured()
            payloadBytes = try encoder.encode(payload)
        } else if let compressed = envelope.compressedPayload {
            payloadBytes = try codec.decompress(compressed)
        } else if envelope.encryptedPayload != nil {
            // Can't consolidate encrypted backups without password
            throw NSError(domain: "IncrementalBackupService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Cannot consolidate encrypted backup without password"
            ])
        } else {
            throw NSError(domain: "IncrementalBackupService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload"
            ])
        }

        return try decoder.decode(BackupPayload.self, from: payloadBytes)
    }
}
