//
//  LessonAssignmentHistoryView+DataLoading.swift
//  Maria's Notebook
//
//  Data loading and cache building for LessonAssignmentHistoryView - extracted for maintainability
//

import SwiftUI
import SwiftData
import os

extension LessonAssignmentHistoryView {

    // MARK: - Data Loading

    func loadAssignments(limit: Int? = nil) {
        let presentedState = LessonAssignmentState.presented.rawValue
        var descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == presentedState },
            sortBy: [
                SortDescriptor(\LessonAssignment.presentedAt, order: .reverse),
                SortDescriptor(\LessonAssignment.createdAt, order: .reverse)
            ]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        loadedAssignments = modelContext.safeFetch(descriptor)
        // If we requested a limit and got fewer results, we've loaded all available
        if let limit = limit {
            hasLoadedMore = loadedAssignments.count < limit
        } else {
            hasLoadedMore = false // No limit means we loaded everything
        }
    }

    func loadMoreAssignments() {
        guard !hasLoadedMore else { return }
        let currentCount = loadedAssignments.count
        let presentedState = LessonAssignmentState.presented.rawValue
        var descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == presentedState },
            sortBy: [
                SortDescriptor(\LessonAssignment.presentedAt, order: .reverse),
                SortDescriptor(\LessonAssignment.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = currentCount + Self.loadMoreCount
        let newResults = modelContext.safeFetch(descriptor)
        loadedAssignments = newResults
        // If we got fewer results than requested, we've loaded all available
        hasLoadedMore = newResults.count < currentCount + Self.loadMoreCount
    }

    // MARK: - Cache Building

    /// Builds caches asynchronously to avoid blocking the main thread.
    /// Extracts primitive values on the main thread, then processes on background.
    @MainActor
    func buildCachesAsync() async {
        // Extract primitive/Sendable values on main thread before background processing
        // This avoids passing SwiftData model objects across actor boundaries
        let assignmentIDs: [String] = recentNotes.compactMap { $0.lessonAssignment?.id.uuidString }
        let studentData: [(UUID, String, String)] = safeStudents.map { ($0.id, $0.firstName, $0.lastName) }
        let lessonData: [(UUID, String)] = lessons.map { ($0.id, $0.name) }

        // Build caches on background thread using only Sendable data
        let (counts, sNames, lTitles) = await Task.detached(priority: .userInitiated) {
            // Build notes count cache
            var counts: [String: Int] = [:]
            for assignmentID in assignmentIDs {
                counts[assignmentID, default: 0] += 1
            }

            // Build student name cache
            var sNames: [UUID: String] = [:]
            for (id, firstName, lastName) in studentData {
                let first = firstName.trimmed()
                let last = lastName.trimmed()
                let li = last.first.map { String($0).uppercased() } ?? ""
                sNames[id] = li.isEmpty ? first : "\(first) \(li)."
            }

            // Build lesson title cache
            var lTitles: [UUID: String] = [:]
            for (id, name) in lessonData {
                lTitles[id] = LessonFormatter.titleOrFallback(name, fallback: "Lesson")
            }

            return (counts, sNames, lTitles)
        }.value

        // Assign on main thread
        notesCountCache = counts
        studentNameCache = sNames
        lessonTitleCache = lTitles
    }

    // MARK: - Delete

    func deleteAssignment(_ assignment: LessonAssignment) {
        modelContext.delete(assignment)
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save assignment deletion: \(error)")
        }
        // Reload to reflect deletion
        loadAssignments(limit: loadedAssignments.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
    }
}
