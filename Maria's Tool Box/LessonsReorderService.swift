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
}
