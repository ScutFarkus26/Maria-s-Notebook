import Foundation
import CoreData
import OSLog

// MARK: - Backup Fetch Helpers

/// Helpers for safely fetching data during backup operations.
enum BackupFetchHelpers {
    private static let logger = Logger.backup

    // MARK: - Safe Fetch

    /// Safely fetches all entities of a type, returning empty array on failure.
    static func safeFetch<T: NSManagedObject>(_ type: T.Type, using context: NSManagedObjectContext) -> [T] {
        let descriptor = NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self))
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    // MARK: - Batched Fetch

    /// Fetches entities in batches to avoid memory pressure on large datasets.
    static func safeFetchInBatches<T: NSManagedObject>(
        _ type: T.Type,
        using context: NSManagedObjectContext,
        batchSize: Int = BatchingConstants.defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0

        while true {
            let descriptor = NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self))
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
    static func safeFetchInBatchesWithErrorHandling<T: NSManagedObject>(
        _ type: T.Type,
        using context: NSManagedObjectContext,
        batchSize: Int = BatchingConstants.defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0

        while true {
            let descriptor = NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self))
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
    static func safeFetchWithErrorHandling<T: NSManagedObject>(
        _ type: T.Type,
        using context: NSManagedObjectContext
    ) -> [T] {
        do {
            return try context.fetch(NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self)))
        } catch {
            logger.warning("Failed to fetch \(T.self): \(error)")
            logger.error("Could not fetch \(type). Skipping this entity type.")
            return []
        }
    }

    // MARK: - Single Entity Fetch

    /// Fetches a single entity by ID.
    /// Uses type-specific predicates to avoid SwiftData generic predicate limitations.
    static func fetchOne<T: NSManagedObject>(
        _ type: T.Type,
        id: UUID,
        using context: NSManagedObjectContext
    ) throws -> T? {
        if let result = try fetchOneCoreEntity(type, id: id, using: context) {
            return result
        }
        return try fetchOneRelationEntity(type, id: id, using: context)
    }

    // MARK: - fetchOne Helpers

    private static func fetchOneCoreEntity<T: NSManagedObject>(
        _ type: T.Type,
        id: UUID,
        using context: NSManagedObjectContext
    ) throws -> T? {
        if type == CDStudent.self {
            let descriptor: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDLesson.self {
            let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // LegacyPresentation removed — fully migrated to CDLessonAssignment
        if type == CDWorkModel.self {
            let descriptor: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        if type == CDNote.self {
            let descriptor: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDNonSchoolDay.self {
            let descriptor: NSFetchRequest<CDNonSchoolDay> = NSFetchRequest(entityName: "NonSchoolDay")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDSchoolDayOverride.self {
            let descriptor: NSFetchRequest<CDSchoolDayOverride> = NSFetchRequest(entityName: "SchoolDayOverride")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDStudentMeeting.self {
            let descriptor: NSFetchRequest<CDStudentMeeting> = NSFetchRequest(entityName: "StudentMeeting")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // Removed: CDPresentation (now uses CDLessonAssignment)
        if type == CDCommunityTopicEntity.self {
            let descriptor: NSFetchRequest<CDCommunityTopicEntity> = NSFetchRequest(entityName: "CommunityTopic")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProposedSolutionEntity.self {
            let descriptor: NSFetchRequest<CDProposedSolutionEntity> = NSFetchRequest(entityName: "ProposedSolution")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }

    private static func fetchOneRelationEntity<T: NSManagedObject>(
        _ type: T.Type,
        id: UUID,
        using context: NSManagedObjectContext
    ) throws -> T? {
        if type == CDCommunityAttachmentEntity.self {
            let descriptor: NSFetchRequest<CDCommunityAttachmentEntity> = NSFetchRequest(
                entityName: "CommunityAttachment"
            )
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDAttendanceRecord.self {
            let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "AttendanceRecord")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDWorkCompletionRecord.self {
            let descriptor: NSFetchRequest<CDWorkCompletionRecord> = NSFetchRequest(
                entityName: "WorkCompletionRecord"
            )
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProject.self {
            let descriptor: NSFetchRequest<CDProject> = NSFetchRequest(entityName: "Project")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectSession.self {
            let descriptor: NSFetchRequest<CDProjectSession> = NSFetchRequest(entityName: "ProjectSession")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectRole.self {
            let descriptor: NSFetchRequest<CDProjectRole> = NSFetchRequest(entityName: "ProjectRole")
            descriptor.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }
}
