// ConflictResolutionService.swift
// Handles conflict resolution strategies for backup restore merge mode

import Foundation
import SwiftData
import OSLog

/// Service for resolving conflicts when merging backup data with existing data
@MainActor
public final class ConflictResolutionService {
    private static let logger = Logger.backup

    // MARK: - Types

    /// Strategy for resolving conflicts when IDs match
    public enum ConflictStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
        /// Skip importing records that already exist (current default behavior)
        case skipExisting = "Skip Existing"
        /// Replace with backup version if backup is newer (based on updatedAt)
        case newerWins = "Newer Wins"
        /// Always keep the local/existing version
        case keepLocal = "Keep Local"
        /// Always use the backup version
        case useBackup = "Use Backup"
        /// Ask user to decide for each conflict (generates preview)
        case manual = "Manual"

        public var id: String { rawValue }

        public var description: String {
            switch self {
            case .skipExisting:
                return "Records in the backup that already exist locally will be skipped."
            case .newerWins:
                return "The more recently updated version will be kept (based on updatedAt timestamp)."
            case .keepLocal:
                return "Always keep your current local data; backup records are ignored if they exist locally."
            case .useBackup:
                return "Replace local records with backup versions when IDs match."
            case .manual:
                return "Review each conflict and choose which version to keep."
            }
        }
    }

    /// Represents a single conflict between local and backup data
    public struct Conflict: Identifiable, Sendable {
        public let id: UUID
        public let entityType: String
        public let entityID: UUID
        public let localUpdatedAt: Date?
        public let backupUpdatedAt: Date?
        public let localSummary: String
        public let backupSummary: String
        public var resolution: ConflictResolution

        public var recommendedResolution: ConflictResolution {
            guard let local = localUpdatedAt, let backup = backupUpdatedAt else {
                return .useBackup // If no dates, prefer backup
            }
            return backup > local ? .useBackup : .keepLocal
        }
    }

    /// Resolution for a single conflict
    public enum ConflictResolution: String, CaseIterable, Sendable {
        case keepLocal = "Keep Local"
        case useBackup = "Use Backup"
    }

    /// Result of conflict analysis
    public struct ConflictAnalysis: Sendable {
        public let conflicts: [Conflict]
        public let autoResolvable: Int
        public let requiresManualReview: Int

        public var totalConflicts: Int { conflicts.count }
        public var isEmpty: Bool { conflicts.isEmpty }
    }

    // MARK: - Properties

    private let codec = BackupCodec()

    // MARK: - Public API

    /// Analyzes conflicts between backup payload and existing data
    /// - Parameters:
    ///   - payload: The backup payload to analyze
    ///   - modelContext: The SwiftData model context
    ///   - strategy: The conflict resolution strategy
    /// - Returns: Analysis of all conflicts found
    public func analyzeConflicts(
        payload: BackupPayload,
        modelContext: ModelContext,
        strategy: ConflictStrategy
    ) -> ConflictAnalysis {
        var conflicts: [Conflict] = []

        // Analyze Students
        conflicts.append(contentsOf: analyzeStudentConflicts(
            payload.students,
            modelContext: modelContext
        ))

        // Analyze Lessons
        conflicts.append(contentsOf: analyzeLessonConflicts(
            payload.lessons,
            modelContext: modelContext
        ))

        // Analyze StudentLessons
        conflicts.append(contentsOf: analyzeStudentLessonConflicts(
            payload.studentLessons,
            modelContext: modelContext
        ))

        // Analyze Notes
        conflicts.append(contentsOf: analyzeNoteConflicts(
            payload.notes,
            modelContext: modelContext
        ))

        // Analyze Projects
        conflicts.append(contentsOf: analyzeProjectConflicts(
            payload.projects,
            modelContext: modelContext
        ))

        // Apply strategy-based auto-resolution
        var autoResolvable = 0
        for i in conflicts.indices {
            switch strategy {
            case .skipExisting, .keepLocal:
                conflicts[i].resolution = .keepLocal
                autoResolvable += 1
            case .useBackup:
                conflicts[i].resolution = .useBackup
                autoResolvable += 1
            case .newerWins:
                conflicts[i].resolution = conflicts[i].recommendedResolution
                autoResolvable += 1
            case .manual:
                // Keep default resolution, requires manual review
                conflicts[i].resolution = conflicts[i].recommendedResolution
            }
        }

        let requiresManualReview = strategy == .manual ? conflicts.count : 0

        return ConflictAnalysis(
            conflicts: conflicts,
            autoResolvable: autoResolvable,
            requiresManualReview: requiresManualReview
        )
    }

    /// Applies conflict resolutions during import
    /// - Parameters:
    ///   - conflicts: The conflicts with their resolutions
    ///   - payload: The backup payload
    ///   - modelContext: The SwiftData model context
    /// - Returns: Number of records updated
    public func applyResolutions(
        conflicts: [Conflict],
        payload: BackupPayload,
        modelContext: ModelContext
    ) throws -> Int {
        var updatedCount = 0

        for conflict in conflicts where conflict.resolution == .useBackup {
            switch conflict.entityType {
            case "Student":
                if let dto = payload.students.first(where: { $0.id == conflict.entityID }) {
                    try updateStudent(dto, in: modelContext)
                    updatedCount += 1
                }
            case "Lesson":
                if let dto = payload.lessons.first(where: { $0.id == conflict.entityID }) {
                    try updateLesson(dto, in: modelContext)
                    updatedCount += 1
                }
            case "StudentLesson":
                if let dto = payload.studentLessons.first(where: { $0.id == conflict.entityID }) {
                    try updateStudentLesson(dto, in: modelContext)
                    updatedCount += 1
                }
            case "Note":
                if let dto = payload.notes.first(where: { $0.id == conflict.entityID }) {
                    try updateNote(dto, in: modelContext)
                    updatedCount += 1
                }
            case "Project":
                if let dto = payload.projects.first(where: { $0.id == conflict.entityID }) {
                    try updateProject(dto, in: modelContext)
                    updatedCount += 1
                }
            default:
                break
            }
        }

        if updatedCount > 0 {
            try modelContext.save()
        }

        return updatedCount
    }

    // MARK: - Conflict Analysis Helpers

    private func analyzeStudentConflicts(
        _ dtos: [StudentDTO],
        modelContext: ModelContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == dtoID })
            descriptor.fetchLimit = 1
            let existing: Student?
            do {
                existing = try modelContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch student: \(error)")
                continue
            }
            guard let existing = existing else { continue }

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "Student",
                entityID: dto.id,
                localUpdatedAt: nil, // Student doesn't have updatedAt
                backupUpdatedAt: dto.updatedAt,
                localSummary: "\(existing.firstName) \(existing.lastName)",
                backupSummary: "\(dto.firstName) \(dto.lastName)",
                resolution: .keepLocal
            ))
        }

        return conflicts
    }

    private func analyzeLessonConflicts(
        _ dtos: [LessonDTO],
        modelContext: ModelContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == dtoID })
            descriptor.fetchLimit = 1
            let existing: Lesson?
            do {
                existing = try modelContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch lesson: \(error)")
                continue
            }
            guard let existing = existing else { continue }

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "Lesson",
                entityID: dto.id,
                localUpdatedAt: nil, // Lesson doesn't have updatedAt
                backupUpdatedAt: dto.updatedAt,
                localSummary: existing.name,
                backupSummary: dto.name,
                resolution: .keepLocal
            ))
        }

        return conflicts
    }

    private func analyzeStudentLessonConflicts(
        _ dtos: [StudentLessonDTO],
        modelContext: ModelContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        // StudentLesson model removed — check for conflicts against LessonAssignment instead
        for dto in dtos {
            let dtoID = dto.id
            var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == dtoID })
            descriptor.fetchLimit = 1
            let existing: LessonAssignment?
            do {
                existing = try modelContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch lesson assignment for legacy student lesson: \(error)")
                continue
            }
            guard let existing = existing else { continue }

            let localSummary = "Scheduled: \(existing.scheduledFor?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")"
            let backupSummary = "Scheduled: \(dto.scheduledFor?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")"

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "StudentLesson",
                entityID: dto.id,
                localUpdatedAt: nil,
                backupUpdatedAt: nil,
                localSummary: localSummary,
                backupSummary: backupSummary,
                resolution: .keepLocal
            ))
        }

        return conflicts
    }

    private func analyzeNoteConflicts(
        _ dtos: [NoteDTO],
        modelContext: ModelContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == dtoID })
            descriptor.fetchLimit = 1
            let existing: Note?
            do {
                existing = try modelContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch note: \(error)")
                continue
            }
            guard let existing = existing else { continue }

            let localPreview = String(existing.body.prefix(50)) + (existing.body.count > 50 ? "…" : "")
            let backupPreview = String(dto.body.prefix(50)) + (dto.body.count > 50 ? "…" : "")

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "Note",
                entityID: dto.id,
                localUpdatedAt: existing.updatedAt,
                backupUpdatedAt: dto.updatedAt,
                localSummary: localPreview,
                backupSummary: backupPreview,
                resolution: .keepLocal
            ))
        }

        return conflicts
    }

    private func analyzeProjectConflicts(
        _ dtos: [ProjectDTO],
        modelContext: ModelContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == dtoID })
            descriptor.fetchLimit = 1
            let existing: Project?
            do {
                existing = try modelContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch project: \(error)")
                continue
            }
            guard let existing = existing else { continue }

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "Project",
                entityID: dto.id,
                localUpdatedAt: nil,
                backupUpdatedAt: nil,
                localSummary: existing.title,
                backupSummary: dto.title,
                resolution: .keepLocal
            ))
        }

        return conflicts
    }

    // MARK: - Update Helpers

    private func updateStudent(_ dto: StudentDTO, in modelContext: ModelContext) throws {
        let dtoID = dto.id
        var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == dtoID })
        descriptor.fetchLimit = 1
        let student: Student?
        do {
            student = try modelContext.fetch(descriptor).first
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch student: \(error)")
            return
        }
        guard let student = student else { return }

        student.firstName = dto.firstName
        student.lastName = dto.lastName
        student.birthday = dto.birthday
        student.dateStarted = dto.dateStarted
        student.level = dto.level == .upper ? .upper : .lower
        student.nextLessons = dto.nextLessons.map { $0.uuidString }
        student.manualOrder = dto.manualOrder
    }

    private func updateLesson(_ dto: LessonDTO, in modelContext: ModelContext) throws {
        let dtoID = dto.id
        var descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == dtoID })
        descriptor.fetchLimit = 1
        let lesson: Lesson?
        do {
            lesson = try modelContext.fetch(descriptor).first
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch lesson: \(error)")
            return
        }
        guard let lesson = lesson else { return }

        lesson.name = dto.name
        lesson.subject = dto.subject
        lesson.group = dto.group
        lesson.orderInGroup = dto.orderInGroup
        lesson.subheading = dto.subheading
        lesson.writeUp = dto.writeUp
        if let pages = dto.pagesFileRelativePath {
            lesson.pagesFileRelativePath = pages
        }
    }

    private func updateStudentLesson(_ dto: StudentLessonDTO, in modelContext: ModelContext) throws {
        // StudentLesson model removed — update corresponding LessonAssignment instead
        let dtoID = dto.id
        var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == dtoID })
        descriptor.fetchLimit = 1
        let la: LessonAssignment?
        do {
            la = try modelContext.fetch(descriptor).first
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch lesson assignment: \(error)")
            return
        }
        guard let la = la else { return }

        la.scheduledFor = dto.scheduledFor
        if let givenAt = dto.givenAt {
            la.markPresented(at: givenAt)
        }
        la.notes = dto.notes
        la.needsPractice = dto.needsPractice
        la.needsAnotherPresentation = dto.needsAnotherPresentation
        la.followUpWork = dto.followUpWork
    }

    private func updateNote(_ dto: NoteDTO, in modelContext: ModelContext) throws {
        let dtoID = dto.id
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == dtoID })
        descriptor.fetchLimit = 1
        let note: Note?
        do {
            note = try modelContext.fetch(descriptor).first
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch note: \(error)")
            return
        }
        guard let note = note else { return }

        note.body = dto.body
        note.updatedAt = dto.updatedAt
        note.isPinned = dto.isPinned
        if let data = dto.scope.data(using: .utf8) {
            do {
                let scope = try JSONDecoder().decode(NoteScope.self, from: data)
                note.scope = scope
            } catch {
                Self.logger.warning("Failed to decode note scope: \(error)")
            }
        }
    }

    private func updateProject(_ dto: ProjectDTO, in modelContext: ModelContext) throws {
        let dtoID = dto.id
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == dtoID })
        descriptor.fetchLimit = 1
        let project: Project?
        do {
            project = try modelContext.fetch(descriptor).first
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to fetch project: \(error)")
            return
        }
        guard let project = project else { return }

        project.title = dto.title
        project.bookTitle = dto.bookTitle
        project.memberStudentIDs = dto.memberStudentIDs
    }
}
