// ProgressionRootViewModel.swift
// ViewModel for the Progression landing page.

import Foundation
import CoreData
import OSLog

/// Loads area/sequence summaries for the Progression landing page.
@Observable
@MainActor
final class ProgressionRootViewModel {
    private static let logger = Logger.app_

    private(set) var groupSummaries: [SequenceSummary] = []
    private(set) var isLoading = false

    // MARK: - Data Loading

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let allLessons = fetchAllLessons(context: context)
        let allPresentations = fetchPresentations(context: context)
        let allWork = fetchAllWork(context: context)
        let allStudents = fetchAllStudents(context: context)
        let visibleStudents = TestStudentsFilter.filterVisible(allStudents.filterEnrolled())
        let visibleStudentIDs = Set(visibleStudents.compactMap { $0.id?.uuidString })

        // Pre-index presentations and work by lessonID for O(1) lookups
        let presentationsByLesson = Dictionary(grouping: allPresentations) { $0.lessonID }
        let workByLesson = Dictionary(grouping: allWork) { $0.lessonID }

        // Group lessons by area/sequence
        let lessonsBySequence = Dictionary(grouping: allLessons) {
            AreaSequencePair(area: $0.area.trimmed(), sequence: $0.sequence.trimmed())
        }

        let staleThreshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        var summaries: [SequenceSummary] = []

        for (key, lessons) in lessonsBySequence {
            guard !key.area.isEmpty, !key.sequence.isEmpty else { continue }

            let sorted = lessons.sorted { $0.orderInSequence < $1.orderInSequence }

            // Collect presentations and work for this sequence using pre-indexed dictionaries
            var groupPresentations: [CDLessonAssignment] = []
            var groupWork: [CDWorkModel] = []
            // Also build a lessonID → orderInSequence lookup for this sequence
            var orderByLessonID: [String: Int] = [:]

            for lesson in sorted {
                let lessonIDStr = lesson.id?.uuidString ?? ""
                orderByLessonID[lessonIDStr] = Int(lesson.orderInSequence)
                if let pres = presentationsByLesson[lessonIDStr] {
                    groupPresentations.append(contentsOf: pres.filter { $0.presentedAt != nil })
                }
                if let work = workByLesson[lessonIDStr] {
                    groupWork.append(contentsOf: work)
                }
            }

            // Collect unique visible students who have presentations in this sequence
            var studentIDsInSequence = Set<String>()
            for la in groupPresentations {
                for sid in la.studentIDs where visibleStudentIDs.contains(sid) {
                    studentIDsInSequence.insert(sid)
                }
            }

            guard !studentIDsInSequence.isEmpty else { continue }

            // Pre-index sequence work by studentID
            let groupWorkByStudent = Dictionary(grouping: groupWork) { $0.studentID }

            // Count active work in the sequence
            let activeWorkCount = groupWork.filter { w in
                studentIDsInSequence.contains(w.studentID) && w.status != .complete
            }.count

            // Per-student readiness analysis
            var readyCount = 0
            var needsAttentionCount = 0

            for studentID in studentIDsInSequence {
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
                        (w.lastTouchedAt ?? w.createdAt ?? .distantPast) < staleThreshold
                    }
                    if hasStaleWork {
                        needsAttentionCount += 1
                    }
                }
            }

            // Find furthest lesson name across all students
            let allPresentedLessonIDs = Set(groupPresentations.map(\.lessonID))
            let furthestLesson = sorted.last { allPresentedLessonIDs.contains($0.id?.uuidString ?? "") }

            let totalPractice = groupWork.reduce(0) { $0 + $1.practiceCount }

            summaries.append(SequenceSummary(
                id: "\(key.area)|\(key.sequence)",
                area: key.area,
                sequence: key.sequence,
                lessonCount: sorted.count,
                studentCount: studentIDsInSequence.count,
                activeWorkCount: activeWorkCount,
                totalPracticeCount: totalPractice,
                studentsReadyForNext: readyCount,
                studentsNeedingAttention: needsAttentionCount,
                furthestLessonName: furthestLesson?.name
            ))
        }

        groupSummaries = summaries.sorted { ($0.area, $0.sequence) < ($1.area, $1.sequence) }
    }

    // MARK: - Data Fetching

    private func fetchAllLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
        ]
        return context.safeFetch(request)
    }

    private func fetchPresentations(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let descriptor = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        return context.safeFetch(descriptor)
    }

    private func fetchAllWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let descriptor = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        return context.safeFetch(descriptor)
    }

    private func fetchAllStudents(context: NSManagedObjectContext) -> [CDStudent] {
        let descriptor = { let r = NSFetchRequest<CDStudent>(entityName: "Student"); r.sortDescriptors = CDStudent.sortByName; return r }()
        return context.safeFetch(descriptor)
    }
}

// MARK: - Helper

private struct AreaSequencePair: Hashable {
    let area: String
    let sequence: String
}
