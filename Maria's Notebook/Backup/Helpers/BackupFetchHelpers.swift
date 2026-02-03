import Foundation
import SwiftData

// MARK: - Backup Fetch Helpers

/// Helpers for safely fetching data during backup operations.
enum BackupFetchHelpers {

    // MARK: - Safe Fetch

    /// Safely fetches all entities of a type, returning empty array on failure.
    static func safeFetch<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> [T] {
        let descriptor = FetchDescriptor<T>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Batched Fetch

    /// Fetches entities in batches to avoid memory pressure on large datasets.
    static func safeFetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { break }

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
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { break }

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
        if let results = try? context.fetch(FetchDescriptor<T>()) {
            return results
        }
        #if DEBUG
        print("BackupService: Warning - Could not fetch \(String(describing: type)). Skipping this entity type.")
        #endif
        return []
    }

    // MARK: - Single Entity Fetch

    /// Fetches a single entity by ID.
    /// Uses type-specific predicates to avoid SwiftData generic predicate limitations.
    static func fetchOne<T: PersistentModel>(
        _ type: T.Type,
        id: UUID,
        using context: ModelContext
    ) throws -> T? {
        if type == Student.self {
            var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == Lesson.self {
            var descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == StudentLesson.self {
            var descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == WorkModel.self {
            var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == WorkPlanItem.self {
            var descriptor = FetchDescriptor<WorkPlanItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == Note.self {
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == NonSchoolDay.self {
            var descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == SchoolDayOverride.self {
            var descriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == StudentMeeting.self {
            var descriptor = FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        // Removed: Presentation (now uses LessonAssignment)
        if type == CommunityTopic.self {
            var descriptor = FetchDescriptor<CommunityTopic>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == ProposedSolution.self {
            var descriptor = FetchDescriptor<ProposedSolution>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == CommunityAttachment.self {
            var descriptor = FetchDescriptor<CommunityAttachment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == AttendanceRecord.self {
            var descriptor = FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == WorkCompletionRecord.self {
            var descriptor = FetchDescriptor<WorkCompletionRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == Project.self {
            var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == ProjectAssignmentTemplate.self {
            var descriptor = FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == ProjectSession.self {
            var descriptor = FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == ProjectRole.self {
            var descriptor = FetchDescriptor<ProjectRole>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == ProjectTemplateWeek.self {
            var descriptor = FetchDescriptor<ProjectTemplateWeek>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        if type == ProjectWeekRoleAssignment.self {
            var descriptor = FetchDescriptor<ProjectWeekRoleAssignment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let arr = try context.fetch(descriptor)
            return arr.first as? T
        }
        return nil
    }
}
