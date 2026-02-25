// GenericEntityFetcher.swift
// Protocol-based approach for reducing code duplication in BackupService

import Foundation
import SwiftData
import OSLog

// MARK: - Identifiable Entity Protocol

/// Protocol for entities that can be fetched by UUID
protocol IdentifiableEntity: PersistentModel {
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

    /// Fetches a single entity by ID using the appropriate predicate
    /// - Parameters:
    ///   - type: The entity type to fetch
    ///   - id: The UUID of the entity
    ///   - context: The SwiftData model context
    /// - Returns: The entity if found, nil otherwise
    func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, context: ModelContext) -> T? {
        // Use type-specific fetchers to work around SwiftData's predicate limitations
        switch type {
        case is Student.Type:
            return fetchStudent(id: id, context: context) as? T
        case is Lesson.Type:
            return fetchLesson(id: id, context: context) as? T
        case is StudentLesson.Type:
            return fetchStudentLesson(id: id, context: context) as? T
        case is WorkModel.Type:
            return fetchWorkModel(id: id, context: context) as? T
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        case is Note.Type:
            return fetchNote(id: id, context: context) as? T
        case is NonSchoolDay.Type:
            return fetchNonSchoolDay(id: id, context: context) as? T
        case is SchoolDayOverride.Type:
            return fetchSchoolDayOverride(id: id, context: context) as? T
        case is StudentMeeting.Type:
            return fetchStudentMeeting(id: id, context: context) as? T
        // Removed: Presentation (now uses LessonAssignment)
        case is CommunityTopic.Type:
            return fetchCommunityTopic(id: id, context: context) as? T
        case is ProposedSolution.Type:
            return fetchProposedSolution(id: id, context: context) as? T
        case is CommunityAttachment.Type:
            return fetchCommunityAttachment(id: id, context: context) as? T
        case is AttendanceRecord.Type:
            return fetchAttendanceRecord(id: id, context: context) as? T
        case is WorkCompletionRecord.Type:
            return fetchWorkCompletionRecord(id: id, context: context) as? T
        case is Project.Type:
            return fetchProject(id: id, context: context) as? T
        case is ProjectAssignmentTemplate.Type:
            return fetchProjectAssignmentTemplate(id: id, context: context) as? T
        case is ProjectSession.Type:
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
    func exists<T: PersistentModel>(_ type: T.Type, id: UUID, context: ModelContext) -> Bool {
        fetchOne(type, id: id, context: context) != nil
    }

    // MARK: - Type-Specific Fetchers

    // These are necessary because SwiftData's #Predicate macro doesn't work with
    // generic types - it requires the concrete type at compile time.
    
    private func safeFetchFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, context: ModelContext, entityName: String) -> T? {
        do {
            return try context.fetch(descriptor).first
        } catch {
            Self.logger.warning("Failed to fetch \(entityName) by ID: \(error)")
            return nil
        }
    }

    private func fetchStudent(id: UUID, context: ModelContext) -> Student? {
        var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "Student")
    }

    private func fetchLesson(id: UUID, context: ModelContext) -> Lesson? {
        var descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "Lesson")
    }

    private func fetchStudentLesson(id: UUID, context: ModelContext) -> StudentLesson? {
        var descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "StudentLesson")
    }

    private func fetchWorkModel(id: UUID, context: ModelContext) -> WorkModel? {
        var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "WorkModel")
    }

    // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn

    private func fetchNote(id: UUID, context: ModelContext) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "Note")
    }

    private func fetchNonSchoolDay(id: UUID, context: ModelContext) -> NonSchoolDay? {
        var descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "NonSchoolDay")
    }

    private func fetchSchoolDayOverride(id: UUID, context: ModelContext) -> SchoolDayOverride? {
        var descriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "SchoolDayOverride")
    }

    private func fetchStudentMeeting(id: UUID, context: ModelContext) -> StudentMeeting? {
        var descriptor = FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "StudentMeeting")
    }

    // Removed: fetchPresentation - model no longer exists (use LessonAssignment instead)

    private func fetchCommunityTopic(id: UUID, context: ModelContext) -> CommunityTopic? {
        var descriptor = FetchDescriptor<CommunityTopic>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CommunityTopic")
    }

    private func fetchProposedSolution(id: UUID, context: ModelContext) -> ProposedSolution? {
        var descriptor = FetchDescriptor<ProposedSolution>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProposedSolution")
    }

    private func fetchCommunityAttachment(id: UUID, context: ModelContext) -> CommunityAttachment? {
        var descriptor = FetchDescriptor<CommunityAttachment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "CommunityAttachment")
    }

    private func fetchAttendanceRecord(id: UUID, context: ModelContext) -> AttendanceRecord? {
        var descriptor = FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "AttendanceRecord")
    }

    private func fetchWorkCompletionRecord(id: UUID, context: ModelContext) -> WorkCompletionRecord? {
        var descriptor = FetchDescriptor<WorkCompletionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "WorkCompletionRecord")
    }

    private func fetchProject(id: UUID, context: ModelContext) -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "Project")
    }

    private func fetchProjectAssignmentTemplate(id: UUID, context: ModelContext) -> ProjectAssignmentTemplate? {
        var descriptor = FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectAssignmentTemplate")
    }

    private func fetchProjectSession(id: UUID, context: ModelContext) -> ProjectSession? {
        var descriptor = FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectSession")
    }

    private func fetchProjectRole(id: UUID, context: ModelContext) -> ProjectRole? {
        var descriptor = FetchDescriptor<ProjectRole>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectRole")
    }

    private func fetchProjectTemplateWeek(id: UUID, context: ModelContext) -> ProjectTemplateWeek? {
        var descriptor = FetchDescriptor<ProjectTemplateWeek>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor, context: context, entityName: "ProjectTemplateWeek")
    }

    private func fetchProjectWeekRoleAssignment(id: UUID, context: ModelContext) -> ProjectWeekRoleAssignment? {
        var descriptor = FetchDescriptor<ProjectWeekRoleAssignment>(predicate: #Predicate { $0.id == id })
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
    static func fetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        context: ModelContext,
        batchSize: Int = defaultBatchSize
    ) -> [T] {
        precondition(batchSize > 0, "Batch size must be positive")
        var allEntities: [T] = []
        var offset = 0

        while true {
            // Use autoreleasepool to release intermediate memory during batch processing
            let batch: [T]? = autoreleasepool {
                var descriptor = FetchDescriptor<T>()
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
    static func fetchInBatchesWithErrorHandling<T: PersistentModel>(
        _ type: T.Type,
        context: ModelContext,
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
                var descriptor = FetchDescriptor<T>()
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
    static func countInsertAndSkip<T, U: PersistentModel>(
        items: [T],
        type: U.Type,
        context: ModelContext,
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
