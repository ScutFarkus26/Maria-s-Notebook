// Maria's Notebook/Lessons/LessonOrderMigration.swift

import Foundation
import OSLog
import CoreData

/// Service for migrating and normalizing lesson ordering indices.
/// Ensures existing lessons have sequential sortIndex values within their area.
enum LessonOrderMigration {
    private static let logger = Logger.lessons
    /// Migrates lessons to have sequential sortIndex values within each area.
    /// Should be called once on app launch or when first needed.
    /// - Parameter context: NSManagedObjectContext to migrate lessons
    /// - Returns: Number of lessons that were updated
    static func migrateSortIndices(context: NSManagedObjectContext) -> Int {
        let descriptor = { let r = NSFetchRequest<CDLesson>(entityName: "Lesson"); r.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)
        ]; return r }()
        
        let allLessons: [CDLesson]
        do {
            allLessons = try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch lessons for sort index migration: \(error)")
            return 0
        }
        
        // Group by area
        var areaSequences: [String: [CDLesson]] = [:]
        for lesson in allLessons {
            let area = lesson.area.trimmed()
            if !area.isEmpty {
                areaSequences[area, default: []].append(lesson)
            }
        }
        
        var updatedCount = 0
        
        // Normalize sortIndex within each area
        for (_, lessons) in areaSequences {
            // Sort by existing orderInSequence, then name for stable ordering
            let sorted = lessons.sorted { lhs, rhs in
                if lhs.orderInSequence != rhs.orderInSequence {
                    return lhs.orderInSequence < rhs.orderInSequence
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            
            // Assign sequential indices starting from 0
            for (index, lesson) in sorted.enumerated() where lesson.sortIndex != Int64(index) {
                lesson.sortIndex = Int64(index)
                updatedCount += 1
            }
        }
        
        if updatedCount > 0 {
            context.safeSave()
        }
        
        return updatedCount
    }

}
