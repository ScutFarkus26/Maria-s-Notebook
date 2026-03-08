import Foundation
import SwiftData

// MARK: - Chain Consolidation

extension IncrementalBackupService {

    /// Container for merged entity maps during consolidation
    private struct MergedEntityMaps {
        var students: [UUID: StudentDTO] = [:]
        var lessons: [UUID: LessonDTO] = [:]
        var lessonAssignments: [UUID: LessonAssignmentDTO] = [:]
        var notes: [UUID: NoteDTO] = [:]
        var nonSchoolDays: [UUID: NonSchoolDayDTO] = [:]
        var schoolDayOverrides: [UUID: SchoolDayOverrideDTO] = [:]
        var studentMeetings: [UUID: StudentMeetingDTO] = [:]
        var communityTopics: [UUID: CommunityTopicDTO] = [:]
        var proposedSolutions: [UUID: ProposedSolutionDTO] = [:]
        var communityAttachments: [UUID: CommunityAttachmentDTO] = [:]
        var attendance: [UUID: AttendanceRecordDTO] = [:]
        var workCompletions: [UUID: WorkCompletionRecordDTO] = [:]
        var projects: [UUID: ProjectDTO] = [:]
        var projectTemplates: [UUID: ProjectAssignmentTemplateDTO] = [:]
        var projectSessions: [UUID: ProjectSessionDTO] = [:]
        var projectRoles: [UUID: ProjectRoleDTO] = [:]
        var projectWeeks: [UUID: ProjectTemplateWeekDTO] = [:]
        var projectWeekAssignments: [UUID: ProjectWeekRoleAssignmentDTO] = [:]
        var latestPreferences: PreferencesDTO?

        // swiftlint:disable:next cyclomatic_complexity
        mutating func merge(_ payload: BackupPayload) {
            for dto in payload.students { students[dto.id] = dto }
            for dto in payload.lessons { lessons[dto.id] = dto }
            for dto in payload.lessonAssignments { lessonAssignments[dto.id] = dto }
            for dto in payload.notes { notes[dto.id] = dto }
            for dto in payload.nonSchoolDays { nonSchoolDays[dto.id] = dto }
            for dto in payload.schoolDayOverrides { schoolDayOverrides[dto.id] = dto }
            for dto in payload.studentMeetings { studentMeetings[dto.id] = dto }
            for dto in payload.communityTopics { communityTopics[dto.id] = dto }
            for dto in payload.proposedSolutions { proposedSolutions[dto.id] = dto }
            for dto in payload.communityAttachments { communityAttachments[dto.id] = dto }
            for dto in payload.attendance { attendance[dto.id] = dto }
            for dto in payload.workCompletions { workCompletions[dto.id] = dto }
            for dto in payload.projects { projects[dto.id] = dto }
            for dto in payload.projectAssignmentTemplates { projectTemplates[dto.id] = dto }
            for dto in payload.projectSessions { projectSessions[dto.id] = dto }
            for dto in payload.projectRoles { projectRoles[dto.id] = dto }
            for dto in payload.projectTemplateWeeks { projectWeeks[dto.id] = dto }
            for dto in payload.projectWeekRoleAssignments { projectWeekAssignments[dto.id] = dto }
            latestPreferences = payload.preferences
        }

        func toPayload() -> BackupPayload {
            BackupPayload(
                items: [],
                students: Array(students.values),
                lessons: Array(lessons.values),
                lessonAssignments: Array(lessonAssignments.values),
                notes: Array(notes.values),
                nonSchoolDays: Array(nonSchoolDays.values),
                schoolDayOverrides: Array(schoolDayOverrides.values),
                studentMeetings: Array(studentMeetings.values),
                communityTopics: Array(communityTopics.values),
                proposedSolutions: Array(proposedSolutions.values),
                communityAttachments: Array(communityAttachments.values),
                attendance: Array(attendance.values),
                workCompletions: Array(workCompletions.values),
                projects: Array(projects.values),
                projectAssignmentTemplates: Array(projectTemplates.values),
                projectSessions: Array(projectSessions.values),
                projectRoles: Array(projectRoles.values),
                projectTemplateWeeks: Array(projectWeeks.values),
                projectWeekRoleAssignments: Array(projectWeekAssignments.values),
                preferences: latestPreferences ?? PreferencesDTO(values: [:])
            )
        }

        func entityCounts() -> [String: Int] {
            [
                "Student": students.count,
                "Lesson": lessons.count,
                "LessonAssignment": lessonAssignments.count,
                "Note": notes.count,
                "NonSchoolDay": nonSchoolDays.count,
                "SchoolDayOverride": schoolDayOverrides.count,
                "StudentMeeting": studentMeetings.count,
                "CommunityTopic": communityTopics.count,
                "ProposedSolution": proposedSolutions.count,
                "CommunityAttachment": communityAttachments.count,
                "AttendanceRecord": attendance.count,
                "WorkCompletionRecord": workCompletions.count,
                "Project": projects.count,
                "ProjectAssignmentTemplate": projectTemplates.count,
                "ProjectSession": projectSessions.count,
                "ProjectRole": projectRoles.count,
                "ProjectTemplateWeek": projectWeeks.count,
                "ProjectWeekRoleAssignment": projectWeekAssignments.count
            ]
        }
    }

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

        var maps = MergedEntityMaps()
        let totalBackups = Double(backupURLs.count)

        // Process each backup in order (oldest first, newer overwrites older)
        for (index, url) in backupURLs.enumerated() {
            let progressBase = Double(index) / totalBackups * 0.8
            progress(progressBase, "Processing backup \(index + 1) of \(backupURLs.count)...")

            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let payload = try await extractPayload(from: url)
            maps.merge(payload)
        }

        progress(0.8, "Creating consolidated backup...")

        return try finalizeConsolidation(
            maps: maps, to: outputURL, password: password,
            backupCount: backupURLs.count, progress: progress
        )
    }

    // MARK: - Consolidation Helpers

    private func finalizeConsolidation(
        maps: MergedEntityMaps,
        to outputURL: URL,
        password: String?,
        backupCount: Int,
        progress: @escaping BackupService.ProgressCallback
    ) throws -> ConsolidationResult {
        let consolidatedPayload = maps.toPayload()
        let counts = maps.entityCounts()

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

        let envelope = BackupServiceHelpers.buildEnvelope(
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: counts,
            sha256: sha,
            notes: "Consolidated from \(backupCount) incremental backups"
        )

        progress(0.95, "Writing consolidated backup...")
        try BackupServiceHelpers.writeBackupFile(envelope: envelope, to: outputURL, encoder: encoder)

        progress(1.0, "Consolidation complete")

        let totalEntities = counts.values.reduce(0, +)
        let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0

        return ConsolidationResult(
            outputURL: outputURL,
            consolidatedBackupCount: backupCount,
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
