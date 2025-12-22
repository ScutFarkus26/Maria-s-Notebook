import Foundation
import SwiftData

struct ZeroStudentLessonsCleanerSummary {
    let totalFound: Int
    let deleted: Int
    let worksCleared: Int
}

@MainActor
enum StudentLessonCleaner {
    /// Removes StudentLesson records that have zero students and clears any WorkModel.studentLessonID references to them.
    /// - Parameter context: The SwiftData ModelContext to operate on.
    /// - Returns: A summary of the maintenance performed.
    static func removeZeroStudentLessons(using context: ModelContext) throws -> ZeroStudentLessonsCleanerSummary {
        // Fetch all StudentLesson objects
        let all: [StudentLesson] = try context.fetch(FetchDescriptor<StudentLesson>())
        // Identify those with zero students (by persisted IDs)
        let empties: [StudentLesson] = all.filter { $0.studentIDs.isEmpty }
        let totalFound = empties.count
        guard !empties.isEmpty else {
            return ZeroStudentLessonsCleanerSummary(totalFound: 0, deleted: 0, worksCleared: 0)
        }

        // Build a set of IDs to remove for quick lookups
        let emptyIDs: Set<UUID> = Set(empties.map { $0.id })

        // Fetch works that reference any of these StudentLessons and clear the link
        var worksCleared = 0
        let works: [WorkModel] = try context.fetch(FetchDescriptor<WorkModel>())
        for w in works {
            if let slID = w.studentLessonID, emptyIDs.contains(slID) {
                w.studentLessonID = nil
                worksCleared += 1
            }
        }

        // Delete the empty StudentLessons
        var deleted = 0
        for sl in empties {
            context.delete(sl)
            deleted += 1
        }

        try context.save()
        return ZeroStudentLessonsCleanerSummary(totalFound: totalFound, deleted: deleted, worksCleared: worksCleared)
    }
}
