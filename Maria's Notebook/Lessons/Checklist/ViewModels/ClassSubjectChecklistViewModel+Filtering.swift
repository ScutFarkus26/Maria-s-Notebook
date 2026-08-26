// ClassAreaChecklistViewModel+Filtering.swift
// Narrows the checklist grid to the rows and columns the guide is working on.
//
// Both filters are display-only. The matrix and the column labels stay computed
// over the whole roster and the whole area (see `recomputeMatrix`), so opening,
// changing, or clearing a filter is a re-render with no fetches behind it.

import Foundation
import CoreData

extension ClassAreaChecklistViewModel {

    // MARK: - Applying Filters

    /// Recomputes the visible rows and columns from the current filter state.
    /// Cheap enough to call on every filter change; touches no Core Data.
    func applyFilters() {
        let pruned = studentFilterIDs.intersection(Set(rosterStudents.compactMap(\.id)))
        if pruned != studentFilterIDs {
            // A student left the roster (or test students were hidden) while filtered to them.
            // Without this the grid would silently render zero columns.
            studentFilterIDs = pruned
        }
        recomputeDisplayedStudents()
        recomputeVisibleLessons()
        invalidateLessonsCache()
        pruneSelectionToVisible()
    }

    /// Applies the debounced text from the filter field.
    func applyLessonQuery(_ query: String, context: NSManagedObjectContext) {
        let trimmed = query.trimmed()
        guard trimmed != appliedLessonQuery else { return }
        appliedLessonQuery = trimmed
        lessonQueryTokens = ChecklistLessonFilter.tokens(from: trimmed)
        applyFilters()
        refreshOtherAreaMatches(context: context)
    }

    /// Drops both filters and shows the whole area again.
    func clearFilters(context: NSManagedObjectContext) {
        lessonQuery = ""
        appliedLessonQuery = ""
        lessonQueryTokens = []
        studentFilterIDs = []
        applyFilters()
        refreshOtherAreaMatches(context: context)
    }

    // MARK: - Filter Summary

    /// The students the columns are pinned to, in roster order. Empty when unfiltered.
    var selectedFilterStudents: [CDStudent] {
        studentFilterIDs.isEmpty ? [] : students
    }

    /// "12 of 84 lessons · 3 of 14 students", or nil when nothing is filtered.
    var filterSummary: String? {
        var parts: [String] = []
        if !lessonQueryTokens.isEmpty {
            parts.append("\(visibleLessons.count) of \(lessons.count) lessons")
        }
        if !studentFilterIDs.isEmpty {
            parts.append("\(students.count) of \(rosterStudents.count) students")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Matching

    func matchesQuery(_ lesson: CDLesson) -> Bool {
        ChecklistLessonFilter.matches(
            tokens: lessonQueryTokens,
            name: lesson.name,
            sequence: lesson.sequence,
            section: lesson.section
        )
    }

    /// Counts matches in the other curriculum areas, but only while the selected area
    /// has none — the guide searching "algebra" from Language should be told where it
    /// lives rather than shown a blank grid. Anchored on the longest token so the fetch
    /// stays narrow; the full token rule is then applied in memory.
    func refreshOtherAreaMatches(context: NSManagedObjectContext) {
        guard !lessonQueryTokens.isEmpty,
              visibleLessons.isEmpty,
              let anchor = lessonQueryTokens.max(by: { $0.count < $1.count })
        else {
            otherAreaMatches = []
            return
        }

        let descriptor = CDFetchRequest(CDLesson.self)
        descriptor.predicate = NSPredicate(
            format: "name CONTAINS[cd] %@ OR sequence CONTAINS[cd] %@ OR section CONTAINS[cd] %@",
            anchor, anchor, anchor
        )

        let currentArea = selectedArea.trimmed()
        var counts: [String: Int] = [:]
        for lesson in context.safeFetch(descriptor) where matchesQuery(lesson) {
            let area = lesson.area.trimmed()
            guard !area.isEmpty,
                  area.localizedCaseInsensitiveCompare(currentArea) != .orderedSame
            else { continue }
            counts[area, default: 0] += 1
        }

        otherAreaMatches = counts
            .map { ChecklistAreaMatchCount(area: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.area.localizedCaseInsensitiveCompare(rhs.area) == .orderedAscending
            }
    }

    // MARK: - Recomputation

    private func recomputeDisplayedStudents() {
        guard !studentFilterIDs.isEmpty else {
            students = rosterStudents
            return
        }
        students = rosterStudents.filter { student in
            guard let id = student.id else { return false }
            return studentFilterIDs.contains(id)
        }
    }

    private func recomputeVisibleLessons() {
        guard !lessonQueryTokens.isEmpty else {
            visibleLessons = lessons
            visibleSequences = orderedSequences
            return
        }
        let matched = lessons.filter(matchesQuery)
        let matchedSequences = Set(matched.map { $0.sequence.normalizedForComparison() })
        visibleLessons = matched
        visibleSequences = orderedSequences.filter { matchedSequences.contains($0.normalizedForComparison()) }
    }

    /// Selecting cells and then filtering them away would leave the batch toolbar acting
    /// on rows the guide can no longer see, so hidden cells drop out of the selection.
    private func pruneSelectionToVisible() {
        guard !selectedCells.isEmpty else { return }
        let visibleStudentIDs = Set(students.compactMap(\.id))
        let visibleLessonIDs = Set(visibleLessons.compactMap(\.id))
        let kept = selectedCells.filter {
            visibleStudentIDs.contains($0.studentID) && visibleLessonIDs.contains($0.lessonID)
        }
        if kept.count != selectedCells.count {
            selectedCells = kept
        }
    }
}
