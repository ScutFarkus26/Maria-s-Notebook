import Foundation
import CoreData

enum LessonsReorderService {
    /// Reorders lessons within a subset and writes sequential orderInSequence values.
    /// Calls save on the provided context.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the subset
    ///   - toIndex: Target index within the subset
    ///   - subset: The subset of lessons being reordered (e.g., the current sequence view)
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
            l.orderInSequence = Int64(idx)
        }
        try context.save()
    }
    
    /// Reorders lessons within a area (using sortIndex). Normalizes indices after reordering.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the area
    ///   - toIndex: Target index within the area
    ///   - allLessonsInArea: All lessons in the area (across all groups)
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    public static func reorderInArea(
        movingLesson: CDLesson, fromIndex: Int, toIndex: Int,
        allLessonsInArea: [CDLesson], context: NSManagedObjectContext
    ) throws {
        var ordered = allLessonsInArea
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        
        // Update sortIndex for all lessons in the area
        for (idx, lesson) in ordered.enumerated() {
            lesson.sortIndex = Int64(idx)
        }
        
        try context.save()
    }
    
    /// Reorders lessons within a sequence (using orderInSequence). Normalizes indices after reordering.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the sequence
    ///   - toIndex: Target index within the sequence
    ///   - groupLessons: All lessons in the sequence
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    public static func reorderInSequence(
        movingLesson: CDLesson, fromIndex: Int, toIndex: Int,
        groupLessons: [CDLesson], context: NSManagedObjectContext
    ) throws {
        var ordered = groupLessons
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        
        // Update orderInSequence for all lessons in the sequence
        for (idx, lesson) in ordered.enumerated() {
            lesson.orderInSequence = Int64(idx)
        }
        
        try context.save()
    }
}
