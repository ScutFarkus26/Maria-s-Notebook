// Maria's Notebook/Lessons/LessonOrderMigration.swift

import Foundation
import OSLog
import CoreData

/// Service for migrating and normalizing lesson ordering indices.
/// Ensures existing lessons have sequential sortIndex values within their subject.
enum LessonOrderMigration {
    private static let logger = Logger.lessons
    /// Migrates lessons to have sequential sortIndex values within each subject.
    /// Should be called once on app launch or when first needed.
    /// - Parameter context: NSManagedObjectContext to migrate lessons
    /// - Returns: Number of lessons that were updated
    @MainActor
    static func migrateSortIndices(context: NSManagedObjectContext) -> Int {
        let descriptor = { let r = NSFetchRequest<CDLesson>(entityName: "CDLesson"); r.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.subject, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.group, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInGroup, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)
        ]; return r }()
        
        let allLessons: [CDLesson]
        do {
            allLessons = try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch lessons for sort index migration: \(error)")
            return 0
        }
        
        // Group by subject
        var subjectGroups: [String: [CDLesson]] = [:]
        for lesson in allLessons {
            let subject = lesson.subject.trimmed()
            if !subject.isEmpty {
                subjectGroups[subject, default: []].append(lesson)
            }
        }
        
        var updatedCount = 0
        
        // Normalize sortIndex within each subject
        for (_, lessons) in subjectGroups {
            // Sort by existing orderInGroup, then name for stable ordering
            let sorted = lessons.sorted { lhs, rhs in
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
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
    
    /// Normalizes sortIndex for lessons within a specific subject.
    /// Call this after reordering to ensure indices are sequential.
    /// - Parameters:
    ///   - lessons: Lessons to normalize (should all be from the same subject)
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
    
    /// Normalizes orderInGroup for lessons within a specific group.
    /// Call this after reordering within a group.
    /// - Parameters:
    ///   - lessons: Lessons to normalize (should all be from the same group)
    ///   - context: NSManagedObjectContext to save changes
    @MainActor
    static func normalizeOrderInGroup(for lessons: [CDLesson], context: NSManagedObjectContext) {
        guard !lessons.isEmpty else { return }
        
        // Sort by current orderInGroup, then name for stable ordering
        let sorted = lessons.sorted { lhs, rhs in
            if lhs.orderInGroup != rhs.orderInGroup {
                return lhs.orderInGroup < rhs.orderInGroup
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        // Assign sequential indices
        for (index, lesson) in sorted.enumerated() where lesson.orderInGroup != Int64(index) {
            lesson.orderInGroup = Int64(index)
        }
        
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }
    }
}
