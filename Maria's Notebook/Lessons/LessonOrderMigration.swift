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
    @MainActor
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
            do {
                try context.save()
            } catch {
                logger.warning("Failed to save context after sort index migration: \(error)")
            }
        }
        
        return updatedCount
    }
    
    /// Normalizes sortIndex for lessons within a specific area.
    /// Call this after reordering to ensure indices are sequential.
    /// - Parameters:
    ///   - lessons: Lessons to normalize (should all be from the same area)
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    static func normalizeSortIndices(for lessons: [CDLesson], context: NSManagedObjectContext) {
        guard !lessons.isEmpty else { return }
        
        // Sort by current sortIndex, then name for stable ordering
        let sorted = lessons.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        // Assign sequential indices
        for (index, lesson) in sorted.enumerated() where lesson.sortIndex != Int64(index) {
            lesson.sortIndex = Int64(index)
        }
        
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }
    }
    
    /// Normalizes orderInSequence for lessons within a specific sequence.
    /// Call this after reordering within a sequence.
    /// - Parameters:
    ///   - lessons: Lessons to normalize (should all be from the same sequence)
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    static func normalizeOrderInSequence(for lessons: [CDLesson], context: NSManagedObjectContext) {
        guard !lessons.isEmpty else { return }
        
        // Sort by current orderInSequence, then name for stable ordering
        let sorted = lessons.sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence {
                return lhs.orderInSequence < rhs.orderInSequence
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        // Assign sequential indices
        for (index, lesson) in sorted.enumerated() where lesson.orderInSequence != Int64(index) {
            lesson.orderInSequence = Int64(index)
        }
        
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }
    }
}
