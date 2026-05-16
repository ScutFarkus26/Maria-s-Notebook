import Foundation
import CoreData

/// Helper class for fetching entities by ID in the backup system.
/// Consolidates repetitive fetch logic from BackupService.
@MainActor
struct BackupFetchHelper {
    // Fetches a single entity by ID using a type-specific predicate.
    // Returns nil if the entity is not found or the type is not supported.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func fetchOne<T: NSManagedObject>(_ type: T.Type, id: UUID, using context: NSManagedObjectContext) throws -> T? {
        // CDNote: Each model has a custom UUID 'id' property, so we must use type-specific predicates
        if type == CDStudent.self {
            let descriptor = { let r = NSFetchRequest<CDStudent>(entityName: "Student"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDLesson.self {
            let descriptor = { let r = NSFetchRequest<CDLesson>(entityName: "Lesson"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // LegacyPresentation removed — fully migrated to CDLessonAssignment
        if type == CDLessonAssignment.self {
            let descriptor = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDWorkModel.self {
            let descriptor = { let r = NSFetchRequest<CDWorkModel>(entityName: "WorkModel"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        if type == CDNote.self {
            let descriptor = { let r = NSFetchRequest<CDNote>(entityName: "Note"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDNonSchoolDay.self {
            let descriptor = { let r = NSFetchRequest<CDNonSchoolDay>(entityName: "NonSchoolDay"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDSchoolDayOverride.self {
            let descriptor = { let r = NSFetchRequest<CDSchoolDayOverride>(entityName: "SchoolDayOverride"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDStudentMeeting.self {
            let descriptor = { let r = NSFetchRequest<CDStudentMeeting>(entityName: "StudentMeeting"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDCommunityTopicEntity.self {
            let descriptor = { let r = NSFetchRequest<CDCommunityTopicEntity>(entityName: "CommunityTopic"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProposedSolutionEntity.self {
            let descriptor = { let r = NSFetchRequest<CDProposedSolutionEntity>(entityName: "ProposedSolution"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDCommunityAttachmentEntity.self {
            let descriptor = { let r = NSFetchRequest<CDCommunityAttachmentEntity>(entityName: "CommunityAttachment"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDAttendanceRecord.self {
            let descriptor = { let r = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDWorkCompletionRecord.self {
            let descriptor = { let r = NSFetchRequest<CDWorkCompletionRecord>(entityName: "WorkCompletionRecord"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProject.self {
            let descriptor = { let r = NSFetchRequest<CDProject>(entityName: "Project"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectSession.self {
            let descriptor = { let r = NSFetchRequest<CDProjectSession>(entityName: "ProjectSession"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectRole.self {
            let descriptor = { let r = NSFetchRequest<CDProjectRole>(entityName: "ProjectRole"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }
}
