import Foundation
import CoreData

enum LessonsReorderService {
    /// Reorders lessons within a subset and writes sequential orderInGroup values. Calls save on the provided context.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the subset
    ///   - toIndex: Target index within the subset
    ///   - subset: The subset of lessons being reordered (e.g., the current group view)
    ///   - context: NSManagedObjectContext to save changes
    public static func reorder(
        movingLesson: CDLesson, fromIndex: Int, toIndex: Int,
        subset: [CDLesson], context: NSManagedObjectContext
    ) throws {
        var ordered = subset
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        for (idx, l) in ordered.enumerated() {
            l.orderInGroup = Int64(idx)
        }
        try context.save()
    }
    
    /// Reorders lessons within a subject (using sortIndex). Normalizes indices after reordering.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the subject
    ///   - toIndex: Target index within the subject
    ///   - allLessonsInSubject: All lessons in the subject (across all groups)
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    public static func reorderInSubject(
        movingLesson: CDLesson, fromIndex: Int, toIndex: Int,
        allLessonsInSubject: [CDLesson], context: NSManagedObjectContext
    ) throws {
        var ordered = allLessonsInSubject
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        
        // Update sortIndex for all lessons in the subject
        for (idx, lesson) in ordered.enumerated() {
            lesson.sortIndex = Int64(idx)
        }
        
        try context.save()
    }
    
    /// Reorders lessons within a group (using orderInGroup). Normalizes indices after reordering.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the group
    ///   - toIndex: Target index within the group
    ///   - groupLessons: All lessons in the group
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    public static func reorderInGroup(
        movingLesson: CDLesson, fromIndex: Int, toIndex: Int,
        groupLessons: [CDLesson], context: NSManagedObjectContext
    ) throws {
        var ordered = groupLessons
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        
        // Update orderInGroup for all lessons in the group
        for (idx, lesson) in ordered.enumerated() {
            lesson.orderInGroup = Int64(idx)
        }
        
        try context.save()
    }
}
