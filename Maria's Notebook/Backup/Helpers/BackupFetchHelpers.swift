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
        let descriptor = T.fetchRequest() as! NSFetchRequest<T>
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
            var descriptor = T.fetchRequest() as! NSFetchRequest<T>
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
            var descriptor = T.fetchRequest() as! NSFetchRequest<T>
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
            return try context.fetch(T.fetchRequest() as! NSFetchRequest<T>)
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
            var descriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDLesson.self {
            var descriptor = { let r = CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // LegacyPresentation removed — fully migrated to CDLessonAssignment
        if type == CDWorkModel.self {
            var descriptor = { let r = CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        if type == CDNote.self {
            var descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDNonSchoolDay.self {
            var descriptor = { let r = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDSchoolDayOverride.self {
            var descriptor = { let r = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDStudentMeeting.self {
            var descriptor = { let r = CDStudentMeeting.fetchRequest() as! NSFetchRequest<CDStudentMeeting>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // Removed: CDPresentation (now uses CDLessonAssignment)
        if type == CDCommunityTopicEntity.self {
            var descriptor = { let r = CDCommunityTopicEntity.fetchRequest() as! NSFetchRequest<CDCommunityTopicEntity>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProposedSolution.self {
            var descriptor = { let r = ProposedSolution.fetchRequest() as! NSFetchRequest<ProposedSolution>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
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
        if type == CommunityAttachment.self {
            var descriptor = { let r = CommunityAttachment.fetchRequest() as! NSFetchRequest<CommunityAttachment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDAttendanceRecord.self {
            var descriptor = { let r = CDAttendanceRecord.fetchRequest() as! NSFetchRequest<CDAttendanceRecord>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDWorkCompletionRecord.self {
            var descriptor = { let r = CDWorkCompletionRecord.fetchRequest() as! NSFetchRequest<CDWorkCompletionRecord>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProject.self {
            var descriptor = { let r = CDProject.fetchRequest() as! NSFetchRequest<CDProject>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectAssignmentTemplate.self {
            var descriptor = { let r = ProjectAssignmentTemplate.fetchRequest() as! NSFetchRequest<ProjectAssignmentTemplate>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectSession.self {
            var descriptor = { let r = CDProjectSession.fetchRequest() as! NSFetchRequest<CDProjectSession>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectRole.self {
            var descriptor = { let r = ProjectRole.fetchRequest() as! NSFetchRequest<ProjectRole>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectTemplateWeek.self {
            var descriptor = { let r = ProjectTemplateWeek.fetchRequest() as! NSFetchRequest<ProjectTemplateWeek>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == ProjectWeekRoleAssignment.self {
            var descriptor = { let r = ProjectWeekRoleAssignment.fetchRequest() as! NSFetchRequest<ProjectWeekRoleAssignment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }
}
