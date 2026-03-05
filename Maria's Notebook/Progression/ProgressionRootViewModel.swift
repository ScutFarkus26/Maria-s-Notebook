// ProgressionRootViewModel.swift
// ViewModel for the Progression landing page.

import Foundation
import SwiftData
import OSLog

/// Loads subject/group summaries for the Progression landing page.
@Observable
@MainActor
final class ProgressionRootViewModel {
    private static let logger = Logger.app_

    private(set) var groupSummaries: [GroupSummary] = []
    private(set) var isLoading = false

    // MARK: - Data Loading

    func loadData(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        let allLessons = fetchAllLessons(context: context)
        let allPresentations = fetchPresentations(context: context)
        let allWork = fetchAllWork(context: context)
        let allStudents = fetchAllStudents(context: context)
        let visibleStudents = TestStudentsFilter.filterVisible(allStudents)
        let visibleStudentIDs = Set(visibleStudents.map { $0.id.uuidString })

        // Pre-index presentations and work by lessonID for O(1) lookups
        let presentationsByLesson = Dictionary(grouping: allPresentations) { $0.lessonID }
        let workByLesson = Dictionary(grouping: allWork) { $0.lessonID }

        // Group lessons by subject/group
        let lessonsByGroup = Dictionary(grouping: allLessons) {
            SubjectGroupPair(subject: $0.subject.trimmed(), group: $0.group.trimmed())
        }

        let staleThreshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        var summaries: [GroupSummary] = []

        for (key, lessons) in lessonsByGroup {
            guard !key.subject.isEmpty, !key.group.isEmpty else { continue }

            let sorted = lessons.sorted { $0.orderInGroup < $1.orderInGroup }

            // Collect presentations and work for this group using pre-indexed dictionaries
            var groupPresentations: [LessonAssignment] = []
            var groupWork: [WorkModel] = []
            // Also build a lessonID → orderInGroup lookup for this group
            var orderByLessonID: [String: Int] = [:]

            for lesson in sorted {
                let lessonIDStr = lesson.id.uuidString
                orderByLessonID[lessonIDStr] = lesson.orderInGroup
                if let pres = presentationsByLesson[lessonIDStr] {
                    groupPresentations.append(contentsOf: pres.filter { $0.presentedAt != nil })
                }
                if let work = workByLesson[lessonIDStr] {
                    groupWork.append(contentsOf: work)
                }
            }

            // Collect unique visible students who have presentations in this group
            var studentIDsInGroup = Set<String>()
            for la in groupPresentations {
                for sid in la.studentIDs where visibleStudentIDs.contains(sid) {
                    studentIDsInGroup.insert(sid)
                }
            }

            guard !studentIDsInGroup.isEmpty else { continue }

            // Pre-index group work by studentID
            let groupWorkByStudent = Dictionary(grouping: groupWork) { $0.studentID }

            // Count active work in the group
            let activeWorkCount = groupWork.filter { w in
                studentIDsInGroup.contains(w.studentID) && w.status != .complete
            }.count

            // Per-student readiness analysis
            var readyCount = 0
            var needsAttentionCount = 0

            for studentID in studentIDsInGroup {
                let studentPresentations = groupPresentations.filter { $0.studentIDs.contains(studentID) }
                let studentWork = groupWorkByStudent[studentID] ?? []
                let studentActiveWork = studentWork.filter { $0.status != .complete }

                // Find furthest presented lesson order using pre-indexed lookup
                var furthestOrder = -1
                for la in studentPresentations {
                    if let order = orderByLessonID[la.lessonID] {
                        furthestOrder = max(furthestOrder, order)
                    }
                }

                if furthestOrder >= 0 {
                    // Find the lesson ID at the furthest order
                    let furthestLessonID = orderByLessonID.first { $0.value == furthestOrder }?.key
                    if let flID = furthestLessonID {
                        let furthestWork = studentWork.filter { $0.lessonID == flID }
                        let allComplete = !furthestWork.isEmpty && furthestWork.allSatisfy { $0.status == .complete }
                        if allComplete || furthestWork.isEmpty {
                            readyCount += 1
                        }
                    }

                    // Check for stale work (active work with no recent touch)
                    let hasStaleWork = studentActiveWork.contains { w in
                        (w.lastTouchedAt ?? w.createdAt) < staleThreshold
                    }
                    if hasStaleWork {
                        needsAttentionCount += 1
                    }
                }
            }

            // Find furthest lesson name across all students
            let allPresentedLessonIDs = Set(groupPresentations.map { $0.lessonID })
            let furthestLesson = sorted.last { allPresentedLessonIDs.contains($0.id.uuidString) }

            summaries.append(GroupSummary(
                id: "\(key.subject)|\(key.group)",
                subject: key.subject,
                group: key.group,
                lessonCount: sorted.count,
                studentCount: studentIDsInGroup.count,
                activeWorkCount: activeWorkCount,
                studentsReadyForNext: readyCount,
                studentsNeedingAttention: needsAttentionCount,
                furthestLessonName: furthestLesson?.name
            ))
        }

        groupSummaries = summaries.sorted { ($0.subject, $0.group) < ($1.subject, $1.group) }
    }

    // MARK: - Data Fetching

    private func fetchAllLessons(context: ModelContext) -> [Lesson] {
        let descriptor = FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group), SortDescriptor(\Lesson.orderInGroup)]
        )
        return context.safeFetch(descriptor)
    }

    private func fetchPresentations(context: ModelContext) -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>()
        return context.safeFetch(descriptor)
    }

    private func fetchAllWork(context: ModelContext) -> [WorkModel] {
        let descriptor = FetchDescriptor<WorkModel>()
        return context.safeFetch(descriptor)
    }

    private func fetchAllStudents(context: ModelContext) -> [Student] {
        let descriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        return context.safeFetch(descriptor)
    }
}

// MARK: - Helper

private struct SubjectGroupPair: Hashable {
    let subject: String
    let group: String
}
