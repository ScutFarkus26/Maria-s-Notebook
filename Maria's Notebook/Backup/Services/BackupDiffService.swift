// BackupDiffService.swift
// Compares backups and shows what changed between them

import Foundation
import SwiftData

/// Service for comparing backups and showing differences.
/// Useful for understanding what changed since the last backup.
@MainActor
public final class BackupDiffService {

    // MARK: - Properties

    let codec = BackupCodec()

    // MARK: - Public API

    // Compares the current database state with a backup file.
    //
    // - Parameters:
    //   - backupURL: URL of the backup to compare against
    //   - modelContext: The current model context
    //   - password: Optional decryption password
    //   - progress: Progress callback
    // - Returns: Diff showing what changed since the backup
    public func diffWithCurrentData(
        backupURL: URL,
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupDiff {
        let access = backupURL.startAccessingSecurityScopedResource()
        defer { if access { backupURL.stopAccessingSecurityScopedResource() } }

        progress(0.1, "Reading backup file…")
        let backupPayload = try await extractPayload(from: backupURL, password: password)

        progress(0.3, "Analyzing students…")
        let studentDiff = analyzeStudentDiff(
            backupStudents: backupPayload.students,
            modelContext: modelContext
        )

        progress(0.4, "Analyzing lessons…")
        let lessonDiff = analyzeLessonDiff(
            backupLessons: backupPayload.lessons,
            modelContext: modelContext
        )

        progress(0.6, "Analyzing notes…")
        let noteDiff = analyzeNoteDiff(
            backupNotes: backupPayload.notes,
            modelContext: modelContext
        )

        progress(0.7, "Analyzing calendar…")
        let calendarDiff = analyzeCalendarDiff(
            backupNonSchoolDays: backupPayload.nonSchoolDays,
            backupOverrides: backupPayload.schoolDayOverrides,
            modelContext: modelContext
        )

        progress(0.8, "Analyzing projects…")
        let projectDiff = analyzeProjectDiff(
            backupProjects: backupPayload.projects,
            modelContext: modelContext
        )

        progress(0.9, "Analyzing attendance…")
        let attendanceDiff = analyzeAttendanceDiff(
            backupAttendance: backupPayload.attendance,
            modelContext: modelContext
        )

        progress(1.0, "Diff complete")

        let entityDiffs = [
            studentDiff,
            lessonDiff,
            noteDiff,
            calendarDiff,
            projectDiff,
            attendanceDiff
        ].filter { $0.hasChanges }

        return BackupDiff(
            sourceDescription: backupURL.lastPathComponent,
            targetDescription: "Current Data",
            entityDiffs: entityDiffs,
            createdAt: Date()
        )
    }

    /// Compares two backup files.
    ///
    /// - Parameters:
    ///   - olderBackupURL: URL of the older backup
    ///   - newerBackupURL: URL of the newer backup
    ///   - olderPassword: Password for older backup
    ///   - newerPassword: Password for newer backup
    ///   - progress: Progress callback
    /// - Returns: Diff showing what changed between backups
    public func diffBackups(
        olderBackupURL: URL,
        newerBackupURL: URL,
        olderPassword: String? = nil,
        newerPassword: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupDiff {
        let accessOlder = olderBackupURL.startAccessingSecurityScopedResource()
        let accessNewer = newerBackupURL.startAccessingSecurityScopedResource()
        defer {
            if accessOlder { olderBackupURL.stopAccessingSecurityScopedResource() }
            if accessNewer { newerBackupURL.stopAccessingSecurityScopedResource() }
        }

        progress(0.1, "Reading older backup…")
        let olderPayload = try await extractPayload(from: olderBackupURL, password: olderPassword)

        progress(0.3, "Reading newer backup…")
        let newerPayload = try await extractPayload(from: newerBackupURL, password: newerPassword)

        progress(0.5, "Comparing backups…")

        var entityDiffs: [EntityDiff] = []

        // Compare students
        entityDiffs.append(compareStudents(older: olderPayload.students, newer: newerPayload.students))

        // Compare lessons
        entityDiffs.append(compareLessons(older: olderPayload.lessons, newer: newerPayload.lessons))

        // Compare notes
        entityDiffs.append(compareNotes(older: olderPayload.notes, newer: newerPayload.notes))

        // Compare projects
        entityDiffs.append(compareProjects(older: olderPayload.projects, newer: newerPayload.projects))

        progress(1.0, "Comparison complete")

        return BackupDiff(
            sourceDescription: olderBackupURL.lastPathComponent,
            targetDescription: newerBackupURL.lastPathComponent,
            entityDiffs: entityDiffs.filter { $0.hasChanges },
            createdAt: Date()
        )
    }

    // MARK: - Private Helpers

    func extractPayload(from url: URL, password: String?) async throws -> BackupPayload {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let payloadBytes: Data

        if envelope.payload != nil {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            payloadBytes = try encoder.encode(envelope.payload!)
        } else if let compressed = envelope.compressedPayload {
            payloadBytes = try codec.decompress(compressed)
        } else if let encrypted = envelope.encryptedPayload {
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupDiffService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Backup is encrypted. Please provide a password."
                ])
            }
            let decrypted = try codec.decrypt(encrypted, password: password)
            if envelope.manifest.compression != nil {
                payloadBytes = try codec.decompress(decrypted)
            } else {
                payloadBytes = decrypted
            }
        } else {
            throw NSError(domain: "BackupDiffService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload."
            ])
        }

        return try decoder.decode(BackupPayload.self, from: payloadBytes)
    }
}
