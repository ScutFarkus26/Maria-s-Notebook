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
            let arr = try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Lesson.self {
            let arr = try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == StudentLesson.self {
            let arr = try context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkModel.self {
            let arr = try context.fetch(FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkPlanItem.self {
            let arr = try context.fetch(FetchDescriptor<WorkPlanItem>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Note.self {
            let arr = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == NonSchoolDay.self {
            let arr = try context.fetch(FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == SchoolDayOverride.self {
            let arr = try context.fetch(FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == StudentMeeting.self {
            let arr = try context.fetch(FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        // Removed: Presentation (now uses LessonAssignment)
        if type == CommunityTopic.self {
            let arr = try context.fetch(FetchDescriptor<CommunityTopic>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProposedSolution.self {
            let arr = try context.fetch(FetchDescriptor<ProposedSolution>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == CommunityAttachment.self {
            let arr = try context.fetch(FetchDescriptor<CommunityAttachment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == AttendanceRecord.self {
            let arr = try context.fetch(FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkCompletionRecord.self {
            let arr = try context.fetch(FetchDescriptor<WorkCompletionRecord>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Project.self {
            let arr = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectAssignmentTemplate.self {
            let arr = try context.fetch(FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectSession.self {
            let arr = try context.fetch(FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectRole.self {
            let arr = try context.fetch(FetchDescriptor<ProjectRole>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectTemplateWeek.self {
            let arr = try context.fetch(FetchDescriptor<ProjectTemplateWeek>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectWeekRoleAssignment.self {
            let arr = try context.fetch(FetchDescriptor<ProjectWeekRoleAssignment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        return nil
    }
}
