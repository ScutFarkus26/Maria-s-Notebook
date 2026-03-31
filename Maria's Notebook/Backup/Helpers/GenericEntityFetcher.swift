// GenericEntityFetcher.swift
// Protocol-based approach for reducing code duplication in BackupService

import Foundation
import CoreData
import OSLog

// MARK: - Identifiable Entity Protocol

/// Protocol for entities that can be fetched by UUID
protocol IdentifiableEntity: NSManagedObject {
    var id: UUID { get }
}

// MARK: - Entity Fetcher Registry

/// Registry that provides type-safe fetching for all backup entities
/// This eliminates the need for the 20+ type-specific branches in fetchOne
@MainActor
struct EntityFetcherRegistry {
    private static let logger = Logger.backup

    // MARK: - Singleton

    static let shared = EntityFetcherRegistry()

    // MARK: - Generic Fetch

    // Fetches a single entity by ID using the appropriate predicate
    // - Parameters:
    //   - type: The entity type to fetch
    //   - id: The UUID of the entity
    //   - context: The SwiftData model context
    // - Returns: The entity if found, nil otherwise
    // swiftlint:disable:next cyclomatic_complexity
    func fetchOne<T: NSManagedObject>(_ type: T.Type, id: UUID, context: NSManagedObjectContext) -> T? {
        // Use type-specific fetchers to work around SwiftData's predicate limitations
        switch type {
        case is CDStudent.Type:
            return fetchStudent(id: id, context: context) as? T
        case is CDLesson.Type:
            return fetchLesson(id: id, context: context) as? T
        // LegacyPresentation removed — fully migrated to CDLessonAssignment
        case is CDWorkModel.Type:
            return fetchWorkModel(id: id, context: context) as? T
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        case is CDNote.Type:
            return fetchNote(id: id, context: context) as? T
        case is CDNonSchoolDay.Type:
            return fetchNonSchoolDay(id: id, context: context) as? T
        case is CDSchoolDayOverride.Type:
            return fetchSchoolDayOverride(id: id, context: context) as? T
        case is CDStudentMeeting.Type:
            return fetchStudentMeeting(id: id, context: context) as? T
        // Removed: CDPresentation (now uses CDLessonAssignment)
        case is CDCommunityTopicEntity.Type:
            return fetchCommunityTopic(id: id, context: context) as? T
        case is ProposedSolution.Type:
            return fetchProposedSolution(id: id, context: context) as? T
        case is CommunityAttachment.Type:
            return fetchCommunityAttachment(id: id, context: context) as? T
        case is CDAttendanceRecord.Type:
            return fetchAttendanceRecord(id: id, context: context) as? T
        case is CDWorkCompletionRecord.Type:
            return fetchWorkCompletionRecord(id: id, context: context) as? T
        case is CDProject.Type:
            return fetchProject(id: id, context: context) as? T
        case is ProjectAssignmentTemplate.Type:
            return fetchProjectAssignmentTemplate(id: id, context: context) as? T
        case is CDProjectSession.Type:
            return fetchProjectSession(id: id, context: context) as? T
        case is ProjectRole.Type:
            return fetchProjectRole(id: id, context: context) as? T
        case is ProjectTemplateWeek.Type:
            return fetchProjectTemplateWeek(id: id, context: context) as? T
        case is ProjectWeekRoleAssignment.Type:
            return fetchProjectWeekRoleAssignment(id: id, context: context) as? T
        default:
            // Fallback: Try generic fetch if type matches IdentifiableEntity
            return nil
        }
    }

    /// Checks if an entity with the given ID exists
    func exists<T: NSManagedObject>(_ type: T.Type, id: UUID, context: NSManagedObjectContext) -> Bool {
        fetchOne(type, id: id, context: context) != nil
    }

    // MARK: - Type-Specific Fetchers

    // These are necessary because SwiftData's #Predicate macro doesn't work with
    // generic types - it requires the concrete type at compile time.
    
    private func safeFetchFirst<T: NSManagedObject>(
        _ descriptor: NSFetchRequest<T>,
        context: NSManagedObjectContext,
        entityName: String
    ) -> T? {
        do {
            return try context.fetch(descriptor).first
        } catch {
            Self.logger.warning("Failed to fetch \(entityName) by ID: \(error)")
            return nil
        }
    }

    private func fetchStudent(id: UUID, context: NSManagedObjectContext) -> CDStudent? {
        var descriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDStudent")
    }

    private func fetchLesson(id: UUID, context: NSManagedObjectContext) -> CDLesson? {
        var descriptor = { let r = CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDLesson")
    }

    // fetchLegacyPresentation removed — model fully migrated to CDLessonAssignment

    private func fetchWorkModel(id: UUID, context: NSManagedObjectContext) -> CDWorkModel? {
        var descriptor = { let r = CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDWorkModel")
    }

    // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn

    private func fetchNote(id: UUID, context: NSManagedObjectContext) -> CDNote? {
        var descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDNote")
    }

    private func fetchNonSchoolDay(id: UUID, context: NSManagedObjectContext) -> CDNonSchoolDay? {
        var descriptor = { let r = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDNonSchoolDay")
    }

    private func fetchSchoolDayOverride(id: UUID, context: NSManagedObjectContext) -> CDSchoolDayOverride? {
        var descriptor = { let r = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDSchoolDayOverride")
    }

    private func fetchStudentMeeting(id: UUID, context: NSManagedObjectContext) -> CDStudentMeeting? {
        var descriptor = { let r = CDStudentMeeting.fetchRequest() as! NSFetchRequest<CDStudentMeeting>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDStudentMeeting")
    }

    // Removed: fetchPresentation - model no longer exists (use CDLessonAssignment instead)

    private func fetchCommunityTopic(id: UUID, context: NSManagedObjectContext) -> CDCommunityTopicEntity? {
        var descriptor = { let r = CDCommunityTopicEntity.fetchRequest() as! NSFetchRequest<CDCommunityTopicEntity>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDCommunityTopicEntity")
    }

    private func fetchProposedSolution(id: UUID, context: NSManagedObjectContext) -> ProposedSolution? {
        var descriptor = { let r = ProposedSolution.fetchRequest() as! NSFetchRequest<ProposedSolution>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProposedSolution")
    }

    private func fetchCommunityAttachment(id: UUID, context: NSManagedObjectContext) -> CommunityAttachment? {
        var descriptor = { let r = CommunityAttachment.fetchRequest() as! NSFetchRequest<CommunityAttachment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CommunityAttachment")
    }

    private func fetchAttendanceRecord(id: UUID, context: NSManagedObjectContext) -> CDAttendanceRecord? {
        var descriptor = { let r = CDAttendanceRecord.fetchRequest() as! NSFetchRequest<CDAttendanceRecord>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDAttendanceRecord")
    }

    private func fetchWorkCompletionRecord(id: UUID, context: NSManagedObjectContext) -> CDWorkCompletionRecord? {
        var descriptor = { let r = CDWorkCompletionRecord.fetchRequest() as! NSFetchRequest<CDWorkCompletionRecord>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDWorkCompletionRecord")
    }

    private func fetchProject(id: UUID, context: NSManagedObjectContext) -> CDProject? {
        var descriptor = { let r = CDProject.fetchRequest() as! NSFetchRequest<CDProject>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDProject")
    }

    private func fetchProjectAssignmentTemplate(id: UUID, context: NSManagedObjectContext) -> ProjectAssignmentTemplate? {
        var descriptor = { let r = ProjectAssignmentTemplate.fetchRequest() as! NSFetchRequest<ProjectAssignmentTemplate>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectAssignmentTemplate")
    }

    private func fetchProjectSession(id: UUID, context: NSManagedObjectContext) -> CDProjectSession? {
        var descriptor = { let r = CDProjectSession.fetchRequest() as! NSFetchRequest<CDProjectSession>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CDProjectSession")
    }

    private func fetchProjectRole(id: UUID, context: NSManagedObjectContext) -> ProjectRole? {
        var descriptor = { let r = ProjectRole.fetchRequest() as! NSFetchRequest<ProjectRole>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectRole")
    }

    private func fetchProjectTemplateWeek(id: UUID, context: NSManagedObjectContext) -> ProjectTemplateWeek? {
        var descriptor = { let r = ProjectTemplateWeek.fetchRequest() as! NSFetchRequest<ProjectTemplateWeek>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectTemplateWeek")
    }

    private func fetchProjectWeekRoleAssignment(id: UUID, context: NSManagedObjectContext) -> ProjectWeekRoleAssignment? {
        var descriptor = { let r = ProjectWeekRoleAssignment.fetchRequest() as! NSFetchRequest<ProjectWeekRoleAssignment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectWeekRoleAssignment")
    }
}

// MARK: - Batch Fetcher

/// Provides batch fetching utilities for backup operations
@MainActor
struct BatchEntityFetcher {

    nonisolated static let defaultBatchSize = 1000

    /// Fetches all entities of a type in batches to prevent memory issues
    static func fetchInBatches<T: NSManagedObject>(
        _ type: T.Type,
        context: NSManagedObjectContext,
        batchSize: Int = defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0

        while true {
            // Use autoreleasepool to release intermediate memory during batch processing
            let batch: [T]? = autoreleasepool {
                var descriptor = T.fetchRequest() as! NSFetchRequest<T>
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize
                do {
                    return try context.fetch(descriptor)
                } catch {
                    Logger.backup.warning("Failed to fetch batch of \(T.self) at offset \(offset): \(error)")
                    return nil
                }
            }

            guard let fetchedBatch = batch, !fetchedBatch.isEmpty else {
                break
            }

            allEntities.append(contentsOf: fetchedBatch)

            if fetchedBatch.count < batchSize {
                break
            }

            offset += batchSize
        }

        return allEntities
    }

    /// Fetches entities with error handling (continues on errors)
    static func fetchInBatchesWithErrorHandling<T: NSManagedObject>(
        _ type: T.Type,
        context: NSManagedObjectContext,
        batchSize: Int = defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0
        var consecutiveErrors = 0
        let maxConsecutiveErrors = 3

        while consecutiveErrors < maxConsecutiveErrors {
            // Use autoreleasepool to release intermediate memory during batch processing
            let result: Result<[T], Error> = autoreleasepool {
                var descriptor = T.fetchRequest() as! NSFetchRequest<T>
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize

                do {
                    let batch = try context.fetch(descriptor)
                    return .success(batch)
                } catch {
                    return .failure(error)
                }
            }

            switch result {
            case .success(let batch):
                if batch.isEmpty {
                    return allEntities
                }

                allEntities.append(contentsOf: batch)
                consecutiveErrors = 0

                if batch.count < batchSize {
                    return allEntities
                }

                offset += batchSize

            case .failure(let error):
                Logger.backup.error("Error fetching \(type) at offset \(offset): \(error)")
                consecutiveErrors += 1
                offset += batchSize // Skip this batch and try next
            }
        }

        return allEntities
    }
}

// MARK: - Entity Count Helpers

/// Helpers for counting and comparing entities
@MainActor
struct EntityCountHelpers {

    /// Counts entities that would be inserted vs skipped during merge
    static func countInsertAndSkip<T, U: NSManagedObject>(
        items: [T],
        type: U.Type,
        context: NSManagedObjectContext,
        idExtractor: (T) -> UUID
    ) -> (insert: Int, skip: Int) {
        let fetcher = EntityFetcherRegistry.shared
        var insert = 0
        var skip = 0

        for item in items {
            let id = idExtractor(item)
            if fetcher.exists(type, id: id, context: context) {
                skip += 1
            } else {
                insert += 1
            }
        }

        return (insert, skip)
    }
}
