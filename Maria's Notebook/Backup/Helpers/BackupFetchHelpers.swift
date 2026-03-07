import Foundation
import SwiftData
import OSLog

// MARK: - Backup Fetch Helpers

/// Helpers for safely fetching data during backup operations.
enum BackupFetchHelpers {
    private static let logger = Logger.backup

    // MARK: - Safe Fetch

    /// Safely fetches all entities of a type, returning empty array on failure.
    static func safeFetch<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> [T] {
        let descriptor = FetchDescriptor<T>()
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    // MARK: - Batched Fetch

    /// Fetches entities in batches to avoid memory pressure on large datasets.
    static func safeFetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = BatchingConstants.defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch: [T]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                logger.warning("Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
                break
            }
            guard !batch.isEmpty else { break }

            allEntities.append(contentsOf: batch)

            if batch.count < batchSize { break }
            offset += batchSize
        }

        return allEntities
    }

    /// Fetches entities in batches with error handling for potentially corrupted data.
    static func safeFetchInBatchesWithErrorHandling<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = BatchingConstants.defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch: [T]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                logger.warning("Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
                break
            }
            guard !batch.isEmpty else { break }

            allEntities.append(contentsOf: batch)

            if batch.count < batchSize { break }
            offset += batchSize
        }

        return allEntities
    }

    /// Fetches entities with error handling, returning empty array and logging on failure.
    static func safeFetchWithErrorHandling<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext
    ) -> [T] {
        do {
            return try context.fetch(FetchDescriptor<T>())
        } catch {
            logger.warning("Failed to fetch \(T.self): \(error)")
            logger.error("Could not fetch \(type). Skipping this entity type.")
            return []
        }
    }

    // MARK: - Single Entity Fetch

    /// Fetches a single entity by ID.
    /// Uses type-specific predicates to avoid SwiftData generic predicate limitations.
    static func fetchOne<T: PersistentModel>(
        _ type: T.Type,
        id: UUID,
        using context: ModelContext
    ) throws -> T? {
        if let result = try fetchOneCoreEntity(type, id: id, using: context) {
            return result
        }
        return try fetchOneRelationEntity(type, id: id, using: context)
    }

    // MARK: - fetchOne Helpers

    private static func fetchOneCoreEntity<T: PersistentModel>(
        _ type: T.Type,
        id: UUID,
        using context: ModelContext
    ) throws -> T? {
        if type == Student.self {
            var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == Lesson.self {
            var descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // LegacyPresentation removed — fully migrated to LessonAssignment
        if type == WorkModel.self {
            var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        if type == Note.self {
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == NonSchoolDay.self {
            var descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == SchoolDayOverride.self {
            var descriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == StudentMeeting.self {
            var descriptor = FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // Removed: Presentation (now uses LessonAssignment)
        if type == CommunityTopic.self {
            var descriptor = FetchDescriptor<CommunityTopic>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProposedSolution.self {
            var descriptor = FetchDescriptor<ProposedSolution>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }

    private static func fetchOneRelationEntity<T: PersistentModel>(
        _ type: T.Type,
        id: UUID,
        using context: ModelContext
    ) throws -> T? {
        if type == CommunityAttachment.self {
            var descriptor = FetchDescriptor<CommunityAttachment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == AttendanceRecord.self {
            var descriptor = FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == WorkCompletionRecord.self {
            var descriptor = FetchDescriptor<WorkCompletionRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == Project.self {
            var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectAssignmentTemplate.self {
            var descriptor = FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectSession.self {
            var descriptor = FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectRole.self {
            var descriptor = FetchDescriptor<ProjectRole>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectTemplateWeek.self {
            var descriptor = FetchDescriptor<ProjectTemplateWeek>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectWeekRoleAssignment.self {
            var descriptor = FetchDescriptor<ProjectWeekRoleAssignment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }
}
