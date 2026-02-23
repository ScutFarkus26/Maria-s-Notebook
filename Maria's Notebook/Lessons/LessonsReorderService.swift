import Foundation
import SwiftData

enum LessonsReorderService {
    /// Reorders lessons within a subset and writes sequential orderInGroup values. Calls save on the provided context.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the subset
    ///   - toIndex: Target index within the subset
    ///   - subset: The subset of lessons being reordered (e.g., the current group view)
    ///   - context: ModelContext to save changes
    public static func reorder(movingLesson: Lesson, fromIndex: Int, toIndex: Int, subset: [Lesson], context: ModelContext) throws {
        var ordered = subset
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        for (idx, l) in ordered.enumerated() {
            l.orderInGroup = idx
        }
        try context.save()
    }
    
    /// Reorders lessons within a subject (using sortIndex). Normalizes indices after reordering.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the subject
    ///   - toIndex: Target index within the subject
    ///   - allLessonsInSubject: All lessons in the subject (across all groups)
    ///   - context: ModelContext to save changes
    @MainActor
    public static func reorderInSubject(movingLesson: Lesson, fromIndex: Int, toIndex: Int, allLessonsInSubject: [Lesson], context: ModelContext) throws {
        var ordered = allLessonsInSubject
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        
        // Update sortIndex for all lessons in the subject
        for (idx, lesson) in ordered.enumerated() {
            lesson.sortIndex = idx
        }
        
        try context.save()
    }
    
    /// Reorders lessons within a group (using orderInGroup). Normalizes indices after reordering.
    /// - Parameters:
    ///   - movingLesson: The lesson being moved
    ///   - fromIndex: Original index within the group
    ///   - toIndex: Target index within the group
    ///   - groupLessons: All lessons in the group
    ///   - context: ModelContext to save changes
    @MainActor
    public static func reorderInGroup(movingLesson: Lesson, fromIndex: Int, toIndex: Int, groupLessons: [Lesson], context: ModelContext) throws {
        var ordered = groupLessons
        let boundedFrom = max(0, min(ordered.count - 1, fromIndex))
        let item = ordered.remove(at: boundedFrom)
        let boundedTo = max(0, min(ordered.count, toIndex))
        ordered.insert(item, at: boundedTo)
        
        // Update orderInGroup for all lessons in the group
        for (idx, lesson) in ordered.enumerated() {
            lesson.orderInGroup = idx
        }
        
        try context.save()
    }
}
