// swiftlint:disable file_length
// ConflictResolutionService.swift
// Handles conflict resolution strategies for backup restore merge mode

import Foundation
import CoreData
import OSLog

/// Service for resolving conflicts when merging backup data with existing data
@MainActor
// swiftlint:disable:next type_body_length
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
    ///   - viewContext: The SwiftData model context
    ///   - strategy: The conflict resolution strategy
    /// - Returns: Analysis of all conflicts found
    public func analyzeConflicts(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext,
        strategy: ConflictStrategy
    ) -> ConflictAnalysis {
        var conflicts: [Conflict] = []

        // Analyze Students
        conflicts.append(contentsOf: analyzeStudentConflicts(
            payload.students,
            viewContext: viewContext
        ))

        // Analyze Lessons
        conflicts.append(contentsOf: analyzeLessonConflicts(
            payload.lessons,
            viewContext: viewContext
        ))

        // Analyze Notes
        conflicts.append(contentsOf: analyzeNoteConflicts(
            payload.notes,
            viewContext: viewContext
        ))

        // Analyze Projects
        conflicts.append(contentsOf: analyzeProjectConflicts(
            payload.projects,
            viewContext: viewContext
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

    // Applies conflict resolutions during import
    // - Parameters:
    //   - conflicts: The conflicts with their resolutions
    //   - payload: The backup payload
    //   - viewContext: The SwiftData model context
    // - Returns: Number of records updated
    // swiftlint:disable:next cyclomatic_complexity
    public func applyResolutions(
        conflicts: [Conflict],
        payload: BackupPayload,
        viewContext: NSManagedObjectContext
    ) throws -> Int {
        var updatedCount = 0

        for conflict in conflicts where conflict.resolution == .useBackup {
            switch conflict.entityType {
            case "CDStudent":
                if let dto = payload.students.first(where: { $0.id == conflict.entityID }) {
                    try updateStudent(dto, in: viewContext)
                    updatedCount += 1
                }
            case "CDLesson":
                if let dto = payload.lessons.first(where: { $0.id == conflict.entityID }) {
                    try updateLesson(dto, in: viewContext)
                    updatedCount += 1
                }
            case "CDNote":
                if let dto = payload.notes.first(where: { $0.id == conflict.entityID }) {
                    try updateNote(dto, in: viewContext)
                    updatedCount += 1
                }
            case "CDProject":
                if let dto = payload.projects.first(where: { $0.id == conflict.entityID }) {
                    try updateProject(dto, in: viewContext)
                    updatedCount += 1
                }
            default:
                break
            }
        }

        if updatedCount > 0 {
            try viewContext.save()
        }

        return updatedCount
    }

    // MARK: - Conflict Analysis Helpers

    private func analyzeStudentConflicts(
        _ dtos: [StudentDTO],
        viewContext: NSManagedObjectContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
            descriptor.fetchLimit = 1
            let existing: CDStudent?
            do {
                existing = try viewContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch student: \(error)")
                continue
            }
            guard let existing else { continue }

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "CDStudent",
                entityID: dto.id,
                localUpdatedAt: nil, // CDStudent doesn't have updatedAt
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
        viewContext: NSManagedObjectContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = { let r = CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
            descriptor.fetchLimit = 1
            let existing: CDLesson?
            do {
                existing = try viewContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch lesson: \(error)")
                continue
            }
            guard let existing else { continue }

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "CDLesson",
                entityID: dto.id,
                localUpdatedAt: nil, // CDLesson doesn't have updatedAt
                backupUpdatedAt: dto.updatedAt,
                localSummary: existing.name,
                backupSummary: dto.name,
                resolution: .keepLocal
            ))
        }

        return conflicts
    }

    private func analyzeNoteConflicts(
        _ dtos: [NoteDTO],
        viewContext: NSManagedObjectContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
            descriptor.fetchLimit = 1
            let existing: CDNote?
            do {
                existing = try viewContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch note: \(error)")
                continue
            }
            guard let existing else { continue }

            let localPreview = String(existing.body.prefix(50)) + (existing.body.count > 50 ? "…" : "")
            let backupPreview = String(dto.body.prefix(50)) + (dto.body.count > 50 ? "…" : "")

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "CDNote",
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
        viewContext: NSManagedObjectContext
    ) -> [Conflict] {
        var conflicts: [Conflict] = []

        for dto in dtos {
            let dtoID = dto.id
            var descriptor = { let r = CDProject.fetchRequest() as! NSFetchRequest<CDProject>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
            descriptor.fetchLimit = 1
            let existing: CDProject?
            do {
                existing = try viewContext.fetch(descriptor).first
            } catch {
                Self.logger.warning("Failed to fetch project: \(error)")
                continue
            }
            guard let existing else { continue }

            conflicts.append(Conflict(
                id: UUID(),
                entityType: "CDProject",
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

    private func updateStudent(_ dto: StudentDTO, in viewContext: NSManagedObjectContext) throws {
        let dtoID = dto.id
        var descriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
        descriptor.fetchLimit = 1
        let student: CDStudent?
        do {
            student = try viewContext.fetch(descriptor).first
        } catch {
            Self.logger.error("Failed to fetch student: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let student else { return }

        student.firstName = dto.firstName
        student.lastName = dto.lastName
        student.birthday = dto.birthday
        student.dateStarted = dto.dateStarted
        student.level = dto.level == .upper ? .upper : .lower
        student.nextLessonUUIDs = dto.nextLessons
        student.manualOrder = Int64(dto.manualOrder)
    }

    private func updateLesson(_ dto: LessonDTO, in viewContext: NSManagedObjectContext) throws {
        let dtoID = dto.id
        var descriptor = { let r = CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
        descriptor.fetchLimit = 1
        let lesson: CDLesson?
        do {
            lesson = try viewContext.fetch(descriptor).first
        } catch {
            Self.logger.error("Failed to fetch lesson: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let lesson else { return }

        lesson.name = dto.name
        lesson.subject = dto.subject
        lesson.group = dto.group
        lesson.orderInGroup = Int64(dto.orderInGroup)
        lesson.subheading = dto.subheading
        lesson.writeUp = dto.writeUp
        if let pages = dto.pagesFileRelativePath {
            lesson.pagesFileRelativePath = pages
        }
    }

    private func updateNote(_ dto: NoteDTO, in viewContext: NSManagedObjectContext) throws {
        let dtoID = dto.id
        var descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
        descriptor.fetchLimit = 1
        let note: CDNote?
        do {
            note = try viewContext.fetch(descriptor).first
        } catch {
            Self.logger.error("Failed to fetch note: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let note else { return }

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

    private func updateProject(_ dto: ProjectDTO, in viewContext: NSManagedObjectContext) throws {
        let dtoID = dto.id
        var descriptor = { let r = CDProject.fetchRequest() as! NSFetchRequest<CDProject>; r.predicate = NSPredicate(format: "id == %@", dtoID as CVarArg); return r }()
        descriptor.fetchLimit = 1
        let project: CDProject?
        do {
            project = try viewContext.fetch(descriptor).first
        } catch {
            Self.logger.error("Failed to fetch project: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let project else { return }

        project.title = dto.title
        project.bookTitle = dto.bookTitle
        project.memberStudentIDsArray = dto.memberStudentIDs
    }
}
