// BackupDiffService.swift
// Compares backups and shows what changed between them

import Foundation
import SwiftData

/// Service for comparing backups and showing differences.
/// Useful for understanding what changed since the last backup.
@MainActor
public final class BackupDiffService {

    // MARK: - Types

    /// Represents the difference between two backups or between a backup and current data
    public struct BackupDiff: Sendable {
        public let sourceDescription: String
        public let targetDescription: String
        public let entityDiffs: [EntityDiff]
        public let createdAt: Date

        public var totalAdded: Int {
            entityDiffs.reduce(0) { $0 + $1.added.count }
        }

        public var totalRemoved: Int {
            entityDiffs.reduce(0) { $0 + $1.removed.count }
        }

        public var totalModified: Int {
            entityDiffs.reduce(0) { $0 + $1.modified.count }
        }

        public var hasChanges: Bool {
            totalAdded > 0 || totalRemoved > 0 || totalModified > 0
        }

        public var summary: String {
            if !hasChanges {
                return "No changes"
            }
            var parts: [String] = []
            if totalAdded > 0 { parts.append("+\(totalAdded) added") }
            if totalRemoved > 0 { parts.append("-\(totalRemoved) removed") }
            if totalModified > 0 { parts.append("~\(totalModified) modified") }
            return parts.joined(separator: ", ")
        }
    }

    /// Differences for a specific entity type
    public struct EntityDiff: Identifiable, Sendable {
        public let id = UUID()
        public let entityType: String
        public let added: [EntityChange]
        public let removed: [EntityChange]
        public let modified: [EntityModification]

        public var hasChanges: Bool {
            !added.isEmpty || !removed.isEmpty || !modified.isEmpty
        }

        public var changeCount: Int {
            added.count + removed.count + modified.count
        }
    }

    /// Represents an added or removed entity
    public struct EntityChange: Identifiable, Sendable {
        public let id: UUID
        public let entityID: UUID
        public let description: String
        public let timestamp: Date?
    }

    /// Represents a modified entity with field-level changes
    public struct EntityModification: Identifiable, Sendable {
        public let id: UUID
        public let entityID: UUID
        public let description: String
        public let fieldChanges: [FieldChange]
    }

    /// Represents a change to a specific field
    public struct FieldChange: Identifiable, Sendable {
        public let id = UUID()
        public let fieldName: String
        public let oldValue: String
        public let newValue: String
    }

    // MARK: - Properties

    private let codec = BackupCodec()

    // MARK: - Public API

    /// Compares the current database state with a backup file.
    ///
    /// - Parameters:
    ///   - backupURL: URL of the backup to compare against
    ///   - modelContext: The current model context
    ///   - password: Optional decryption password
    ///   - progress: Progress callback
    /// - Returns: Diff showing what changed since the backup
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

        progress(0.5, "Analyzing student lessons…")
        let studentLessonDiff = analyzeStudentLessonDiff(
            backupStudentLessons: backupPayload.studentLessons,
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
            studentLessonDiff,
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

    private func extractPayload(from url: URL, password: String?) async throws -> BackupPayload {
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

    // MARK: - Entity-Specific Diff Analysis

    private func analyzeStudentDiff(
        backupStudents: [StudentDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let currentStudents: [Student]
        do {
            currentStudents = try modelContext.fetch(FetchDescriptor<Student>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current students: \(error)")
            currentStudents = []
        }
        let currentIDs = Set(currentStudents.map { $0.id })
        let backupIDs = Set(backupStudents.map { $0.id })

        // Added (in current but not in backup)
        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = currentStudents
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "\($0.firstName) \($0.lastName)", timestamp: nil) }

        // Removed (in backup but not in current)
        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupStudents
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "\($0.firstName) \($0.lastName)", timestamp: $0.updatedAt) }

        // Modified (in both but different)
        var modified: [EntityModification] = []
        for dto in backupStudents {
            guard let current = currentStudents.first(where: { $0.id == dto.id }) else { continue }
            var changes: [FieldChange] = []

            if current.firstName != dto.firstName {
                changes.append(FieldChange(fieldName: "First Name", oldValue: dto.firstName, newValue: current.firstName))
            }
            if current.lastName != dto.lastName {
                changes.append(FieldChange(fieldName: "Last Name", oldValue: dto.lastName, newValue: current.lastName))
            }
            if current.birthday != dto.birthday {
                changes.append(FieldChange(
                    fieldName: "Birthday",
                    oldValue: dto.birthday.formatted(date: .abbreviated, time: .omitted),
                    newValue: current.birthday.formatted(date: .abbreviated, time: .omitted)
                ))
            }

            if !changes.isEmpty {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: current.id,
                    description: "\(current.firstName) \(current.lastName)",
                    fieldChanges: changes
                ))
            }
        }

        return EntityDiff(entityType: "Student", added: added, removed: removed, modified: modified)
    }

    private func analyzeLessonDiff(
        backupLessons: [LessonDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let currentLessons: [Lesson]
        do {
            currentLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current lessons: \(error)")
            currentLessons = []
        }
        let currentIDs = Set(currentLessons.map { $0.id })
        let backupIDs = Set(backupLessons.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = currentLessons
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.name, timestamp: nil) }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupLessons
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.name, timestamp: $0.updatedAt) }

        var modified: [EntityModification] = []
        for dto in backupLessons {
            guard let current = currentLessons.first(where: { $0.id == dto.id }) else { continue }
            var changes: [FieldChange] = []

            if current.name != dto.name {
                changes.append(FieldChange(fieldName: "Name", oldValue: dto.name, newValue: current.name))
            }
            if current.subject != dto.subject {
                changes.append(FieldChange(fieldName: "Subject", oldValue: dto.subject, newValue: current.subject))
            }
            if current.writeUp != dto.writeUp {
                changes.append(FieldChange(
                    fieldName: "Write-up",
                    oldValue: String(dto.writeUp.prefix(50)) + "…",
                    newValue: String(current.writeUp.prefix(50)) + "…"
                ))
            }

            if !changes.isEmpty {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: current.id,
                    description: current.name,
                    fieldChanges: changes
                ))
            }
        }

        return EntityDiff(entityType: "Lesson", added: added, removed: removed, modified: modified)
    }

    private func analyzeStudentLessonDiff(
        backupStudentLessons: [StudentLessonDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        // StudentLesson model removed — compare against LessonAssignment
        let current: [LessonAssignment]
        do {
            current = try modelContext.fetch(FetchDescriptor<LessonAssignment>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current lesson assignments: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupStudentLessons.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "Student Lesson", timestamp: $0.createdAt) }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupStudentLessons
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "Student Lesson", timestamp: $0.createdAt) }

        return EntityDiff(entityType: "StudentLesson", added: added, removed: removed, modified: [])
    }

    private func analyzeNoteDiff(
        backupNotes: [NoteDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let current: [Note]
        do {
            current = try modelContext.fetch(FetchDescriptor<Note>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current notes: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupNotes.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: String($0.body.prefix(40)), timestamp: $0.createdAt) }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupNotes
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: String($0.body.prefix(40)), timestamp: $0.createdAt) }

        var modified: [EntityModification] = []
        for dto in backupNotes {
            guard let c = current.first(where: { $0.id == dto.id }) else { continue }
            if c.body != dto.body {
                modified.append(EntityModification(
                    id: UUID(),
                    entityID: c.id,
                    description: String(c.body.prefix(40)),
                    fieldChanges: [FieldChange(
                        fieldName: "Body",
                        oldValue: String(dto.body.prefix(50)) + "…",
                        newValue: String(c.body.prefix(50)) + "…"
                    )]
                ))
            }
        }

        return EntityDiff(entityType: "Note", added: added, removed: removed, modified: modified)
    }

    private func analyzeCalendarDiff(
        backupNonSchoolDays: [NonSchoolDayDTO],
        backupOverrides: [SchoolDayOverrideDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let currentNSD: [NonSchoolDay]
        let currentOvr: [SchoolDayOverride]
        do {
            currentNSD = try modelContext.fetch(FetchDescriptor<NonSchoolDay>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current non-school days: \(error)")
            currentNSD = []
        }
        do {
            currentOvr = try modelContext.fetch(FetchDescriptor<SchoolDayOverride>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current school day overrides: \(error)")
            currentOvr = []
        }

        var added: [EntityChange] = []
        var removed: [EntityChange] = []

        // Non-school days
        let currentNSDIDs = Set(currentNSD.map { $0.id })
        let backupNSDIDs = Set(backupNonSchoolDays.map { $0.id })

        for id in currentNSDIDs.subtracting(backupNSDIDs) {
            if let nsd = currentNSD.first(where: { $0.id == id }) {
                added.append(EntityChange(id: UUID(), entityID: id, description: "Non-School Day: \(nsd.date.formatted(date: .abbreviated, time: .omitted))", timestamp: nil))
            }
        }
        for id in backupNSDIDs.subtracting(currentNSDIDs) {
            if let nsd = backupNonSchoolDays.first(where: { $0.id == id }) {
                removed.append(EntityChange(id: UUID(), entityID: id, description: "Non-School Day: \(nsd.date.formatted(date: .abbreviated, time: .omitted))", timestamp: nil))
            }
        }

        // School day overrides
        let currentOvrIDs = Set(currentOvr.map { $0.id })
        let backupOvrIDs = Set(backupOverrides.map { $0.id })

        for id in currentOvrIDs.subtracting(backupOvrIDs) {
            if let ovr = currentOvr.first(where: { $0.id == id }) {
                added.append(EntityChange(id: UUID(), entityID: id, description: "Override: \(ovr.date.formatted(date: .abbreviated, time: .omitted))", timestamp: nil))
            }
        }
        for id in backupOvrIDs.subtracting(currentOvrIDs) {
            if let ovr = backupOverrides.first(where: { $0.id == id }) {
                removed.append(EntityChange(id: UUID(), entityID: id, description: "Override: \(ovr.date.formatted(date: .abbreviated, time: .omitted))", timestamp: nil))
            }
        }

        return EntityDiff(entityType: "Calendar", added: added, removed: removed, modified: [])
    }

    private func analyzeProjectDiff(
        backupProjects: [ProjectDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let current: [Project]
        do {
            current = try modelContext.fetch(FetchDescriptor<Project>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current projects: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupProjects.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.title, timestamp: $0.createdAt) }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupProjects
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.title, timestamp: $0.createdAt) }

        return EntityDiff(entityType: "Project", added: added, removed: removed, modified: [])
    }

    private func analyzeAttendanceDiff(
        backupAttendance: [AttendanceRecordDTO],
        modelContext: ModelContext
    ) -> EntityDiff {
        let current: [AttendanceRecord]
        do {
            current = try modelContext.fetch(FetchDescriptor<AttendanceRecord>())
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch current attendance records: \(error)")
            current = []
        }
        let currentIDs = Set(current.map { $0.id })
        let backupIDs = Set(backupAttendance.map { $0.id })

        let addedIDs = currentIDs.subtracting(backupIDs)
        let added = current
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "Attendance \($0.date.formatted(date: .abbreviated, time: .omitted))", timestamp: nil) }

        let removedIDs = backupIDs.subtracting(currentIDs)
        let removed = backupAttendance
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "Attendance \($0.date.formatted(date: .abbreviated, time: .omitted))", timestamp: nil) }

        return EntityDiff(entityType: "Attendance", added: added, removed: removed, modified: [])
    }

    // MARK: - Backup-to-Backup Comparison

    private func compareStudents(older: [StudentDTO], newer: [StudentDTO]) -> EntityDiff {
        let olderIDs = Set(older.map { $0.id })
        let newerIDs = Set(newer.map { $0.id })

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "\($0.firstName) \($0.lastName)", timestamp: $0.updatedAt) }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: "\($0.firstName) \($0.lastName)", timestamp: $0.updatedAt) }

        return EntityDiff(entityType: "Student", added: added, removed: removed, modified: [])
    }

    private func compareLessons(older: [LessonDTO], newer: [LessonDTO]) -> EntityDiff {
        let olderIDs = Set(older.map { $0.id })
        let newerIDs = Set(newer.map { $0.id })

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.name, timestamp: $0.updatedAt) }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.name, timestamp: $0.updatedAt) }

        return EntityDiff(entityType: "Lesson", added: added, removed: removed, modified: [])
    }

    private func compareNotes(older: [NoteDTO], newer: [NoteDTO]) -> EntityDiff {
        let olderIDs = Set(older.map { $0.id })
        let newerIDs = Set(newer.map { $0.id })

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: String($0.body.prefix(40)), timestamp: $0.updatedAt) }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: String($0.body.prefix(40)), timestamp: $0.updatedAt) }

        return EntityDiff(entityType: "Note", added: added, removed: removed, modified: [])
    }

    private func compareProjects(older: [ProjectDTO], newer: [ProjectDTO]) -> EntityDiff {
        let olderIDs = Set(older.map { $0.id })
        let newerIDs = Set(newer.map { $0.id })

        let addedIDs = newerIDs.subtracting(olderIDs)
        let added = newer
            .filter { addedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.title, timestamp: $0.createdAt) }

        let removedIDs = olderIDs.subtracting(newerIDs)
        let removed = older
            .filter { removedIDs.contains($0.id) }
            .map { EntityChange(id: UUID(), entityID: $0.id, description: $0.title, timestamp: $0.createdAt) }

        return EntityDiff(entityType: "Project", added: added, removed: removed, modified: [])
    }
}
