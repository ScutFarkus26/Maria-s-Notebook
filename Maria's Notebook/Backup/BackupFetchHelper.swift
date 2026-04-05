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
            let descriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDLesson.self {
            let descriptor = { let r = CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // LegacyPresentation removed — fully migrated to CDLessonAssignment
        if type == CDLessonAssignment.self {
            let descriptor = { let r = CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDWorkModel.self {
            let descriptor = { let r = CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        if type == CDNote.self {
            let descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDNonSchoolDay.self {
            let descriptor = { let r = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDSchoolDayOverride.self {
            let descriptor = { let r = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDStudentMeeting.self {
            let descriptor = { let r = CDStudentMeeting.fetchRequest() as! NSFetchRequest<CDStudentMeeting>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDCommunityTopicEntity.self {
            let descriptor = { let r = CDCommunityTopicEntity.fetchRequest() as! NSFetchRequest<CDCommunityTopicEntity>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProposedSolutionEntity.self {
            let descriptor = { let r = CDProposedSolutionEntity.fetchRequest() as! NSFetchRequest<CDProposedSolutionEntity>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDCommunityAttachmentEntity.self {
            let descriptor = { let r = CDCommunityAttachmentEntity.fetchRequest() as! NSFetchRequest<CDCommunityAttachmentEntity>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDAttendanceRecord.self {
            let descriptor = { let r = CDAttendanceRecord.fetchRequest() as! NSFetchRequest<CDAttendanceRecord>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDWorkCompletionRecord.self {
            let descriptor = { let r = CDWorkCompletionRecord.fetchRequest() as! NSFetchRequest<CDWorkCompletionRecord>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProject.self {
            let descriptor = { let r = CDProject.fetchRequest() as! NSFetchRequest<CDProject>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectAssignmentTemplate.self {
            let descriptor = { let r = CDProjectAssignmentTemplate.fetchRequest() as! NSFetchRequest<CDProjectAssignmentTemplate>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectSession.self {
            let descriptor = { let r = CDProjectSession.fetchRequest() as! NSFetchRequest<CDProjectSession>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectRole.self {
            let descriptor = { let r = CDProjectRole.fetchRequest() as! NSFetchRequest<CDProjectRole>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectTemplateWeek.self {
            let descriptor = { let r = CDProjectTemplateWeek.fetchRequest() as! NSFetchRequest<CDProjectTemplateWeek>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        if type == CDProjectWeekRoleAssignment.self {
            let descriptor = { let r = CDProjectWeekRoleAssignment.fetchRequest() as! NSFetchRequest<CDProjectWeekRoleAssignment>; r.predicate = NSPredicate(format: "id == %@", id as CVarArg); return r }()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first as? T
        }
        return nil
    }
}
