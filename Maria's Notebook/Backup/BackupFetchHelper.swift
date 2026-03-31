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
        if type == CDLessonAssignment.self {
            var descriptor = { let r = CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
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
