import Foundation
import SwiftData

/// Helper class for fetching entities by ID in the backup system.
/// Consolidates repetitive fetch logic from BackupService.
@MainActor
struct BackupFetchHelper {
    /// Fetches a single entity by ID using a type-specific predicate.
    /// Returns nil if the entity is not found or the type is not supported.
    static func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, using context: ModelContext) throws -> T? {
        // Note: Each model has a custom UUID 'id' property, so we must use type-specific predicates
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
        if type == StudentLesson.self {
            var descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == LessonAssignment.self {
            var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
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
