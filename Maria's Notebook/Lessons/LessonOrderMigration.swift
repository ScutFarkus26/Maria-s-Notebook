// Maria's Notebook/Lessons/LessonOrderMigration.swift

import Foundation
import SwiftData

/// Service for migrating and normalizing lesson ordering indices.
/// Ensures existing lessons have sequential sortIndex values within their subject.
enum LessonOrderMigration {
    /// Migrates lessons to have sequential sortIndex values within each subject.
    /// Should be called once on app launch or when first needed.
    /// - Parameter context: ModelContext to migrate lessons
    /// - Returns: Number of lessons that were updated
    @MainActor
    static func migrateSortIndices(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Lesson>(sortBy: [
            SortDescriptor(\Lesson.subject),
            SortDescriptor(\Lesson.group),
            SortDescriptor(\Lesson.orderInGroup),
            SortDescriptor(\Lesson.name)
        ])
        
        let allLessons: [Lesson]
        do {
            allLessons = try context.fetch(descriptor)
        } catch {
            print("⚠️ [migrateSortIndices] Failed to fetch lessons: \(error)")
            return 0
        }
        
        // Group by subject
        var subjectGroups: [String: [Lesson]] = [:]
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
            for (index, lesson) in sorted.enumerated() {
                if lesson.sortIndex != index {
                    lesson.sortIndex = index
                    updatedCount += 1
                }
            }
        }
        
        if updatedCount > 0 {
            do {
                try context.save()
            } catch {
                print("⚠️ [migrateSortIndices] Failed to save context: \(error)")
            }
        }
        
        return updatedCount
    }
    
    /// Normalizes sortIndex for lessons within a specific subject.
    /// Call this after reordering to ensure indices are sequential.
    /// - Parameters:
    ///   - lessons: Lessons to normalize (should all be from the same subject)
    ///   - context: ModelContext to save changes
    @MainActor
    static func normalizeSortIndices(for lessons: [Lesson], context: ModelContext) {
        guard !lessons.isEmpty else { return }
        
        // Sort by current sortIndex, then name for stable ordering
        let sorted = lessons.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        // Assign sequential indices
        for (index, lesson) in sorted.enumerated() {
            if lesson.sortIndex != index {
                lesson.sortIndex = index
            }
        }
        
        do {
            try context.save()
        } catch {
            print("⚠️ [normalizeSortIndices] Failed to save context: \(error)")
        }
    }
    
    /// Normalizes orderInGroup for lessons within a specific group.
    /// Call this after reordering within a group.
    /// - Parameters:
    ///   - lessons: Lessons to normalize (should all be from the same group)
    ///   - context: ModelContext to save changes
    @MainActor
    static func normalizeOrderInGroup(for lessons: [Lesson], context: ModelContext) {
        guard !lessons.isEmpty else { return }
        
        // Sort by current orderInGroup, then name for stable ordering
        let sorted = lessons.sorted { lhs, rhs in
            if lhs.orderInGroup != rhs.orderInGroup {
                return lhs.orderInGroup < rhs.orderInGroup
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        // Assign sequential indices
        for (index, lesson) in sorted.enumerated() {
            if lesson.orderInGroup != index {
                lesson.orderInGroup = index
            }
        }
        
        do {
            try context.save()
        } catch {
            print("⚠️ [normalizeOrderInGroup] Failed to save context: \(error)")
        }
    }
}
