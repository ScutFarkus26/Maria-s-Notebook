// TodayLevelFilterService.swift
// Service for filtering lessons and work items by student level.
// Encapsulates level filtering logic used by TodayViewModel.

import Foundation

// MARK: - Today Level Filter Service

/// Service for filtering data by student level.
enum TodayLevelFilterService {

    // MARK: - Lesson Filtering

    /// Filters lessons based on level filter and student visibility.
    /// - Parameters:
    ///   - lessons: The lessons to filter
    ///   - studentsByID: Cached students for level lookup
    ///   - levelFilter: The level filter to apply
    /// - Returns: Filtered lessons matching the criteria
    static func filterLessons(
        _ lessons: [StudentLesson],
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter
    ) -> [StudentLesson] {
        guard levelFilter != .all else {
            // For "all" filter, just ensure students are visible (cached)
            return lessons.filter { sl in
                let ids = sl.resolvedStudentIDs
                if ids.isEmpty { return true }
                return ids.contains { studentsByID[$0] != nil }
            }
        }

        // For specific level filters, check if any visible student matches the level
        return lessons.filter { sl in
            let ids = sl.resolvedStudentIDs
            if ids.isEmpty { return true }
            var anyVisible = false
            var anyVisibleMatching = false
            for sid in ids {
                if let s = studentsByID[sid] {
                    anyVisible = true
                    if levelFilter.matches(s.level) { anyVisibleMatching = true }
                }
            }
            return anyVisible && anyVisibleMatching
        }
    }

    // MARK: - Work Filtering

    /// Filters work items based on level filter.
    /// - Parameters:
    ///   - workItems: The work items to filter
    ///   - studentsByID: Cached students for level lookup
    ///   - levelFilter: The level filter to apply
    /// - Returns: Filtered work items matching the criteria
    static func filterWork(
        _ workItems: [WorkModel],
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter
    ) -> [WorkModel] {
        workItems.filter { work in
            guard let uuid = UUID(uuidString: work.studentID),
                  let student = studentsByID[uuid] else { return false }
            return levelFilter.matches(student.level)
        }
    }
}
