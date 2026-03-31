//
//  LessonAssignmentHistoryView+DataLoading.swift
//  Maria's Notebook
//
//  Data loading and cache building for LessonAssignmentHistoryView - extracted for maintainability
//

import SwiftUI
import CoreData
import os

extension LessonAssignmentHistoryView {

    // MARK: - Data Loading

    func loadAssignments(limit: Int? = nil) {
        let presentedState = LessonAssignmentState.presented.rawValue
        var descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", presentedState as CVarArg)
        descriptor.sortDescriptors = [
                NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false),
                NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)
            ]
        if let limit {
            descriptor.fetchLimit = limit
        }
        loadedAssignments = viewContext.safeFetch(descriptor)
        // If we requested a limit and got fewer results, we've loaded all available
        if let limit {
            hasLoadedMore = loadedAssignments.count < limit
        } else {
            hasLoadedMore = false // No limit means we loaded everything
        }
    }

    func loadMoreAssignments() {
        guard !hasLoadedMore else { return }
        let currentCount = loadedAssignments.count
        let presentedState = LessonAssignmentState.presented.rawValue
        var descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", presentedState as CVarArg)
        descriptor.sortDescriptors = [
                NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false),
                NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)
            ]
        descriptor.fetchLimit = currentCount + Self.loadMoreCount
        let newResults = viewContext.safeFetch(descriptor)
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
        let assignmentIDs: [String] = recentNotes.compactMap { $0.lessonAssignment?.id?.uuidString }
        let studentIDs: [UUID] = safeStudents.compactMap(\.id)
        let studentFirstNames: [String] = safeStudents.compactMap { $0.id != nil ? $0.firstName : nil }
        let studentLastNames: [String] = safeStudents.compactMap { $0.id != nil ? $0.lastName : nil }
        let lessonIDs: [UUID] = lessons.compactMap(\.id)
        let lessonNames: [String] = lessons.compactMap { $0.id != nil ? $0.name : nil }

        // Build caches on background thread using only Sendable data
        let (counts, sNames, lTitles) = await Task.detached(priority: .userInitiated) {
            // Build notes count cache
            var counts: [String: Int] = [:]
            for assignmentID in assignmentIDs {
                counts[assignmentID, default: 0] += 1
            }

            // Build student name cache
            var sNames: [UUID: String] = [:]
            for idx in studentIDs.indices {
                let first = studentFirstNames[idx].trimmed()
                let last = studentLastNames[idx].trimmed()
                let li = last.first.map { String($0).uppercased() } ?? ""
                sNames[studentIDs[idx]] = li.isEmpty ? first : "\(first) \(li)."
            }

            // Build lesson title cache
            var lTitles: [UUID: String] = [:]
            for idx in lessonIDs.indices {
                lTitles[lessonIDs[idx]] = LessonFormatter.titleOrFallback(lessonNames[idx], fallback: "Lesson")
            }

            return (counts, sNames, lTitles)
        }.value

        // Assign on main thread
        notesCountCache = counts
        studentNameCache = sNames
        lessonTitleCache = lTitles
    }

    // MARK: - Delete

    func deleteAssignment(_ assignment: CDLessonAssignment) {
        viewContext.delete(assignment)
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save assignment deletion: \(error)")
        }
        // Reload to reflect deletion
        loadAssignments(limit: loadedAssignments.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
    }
}
