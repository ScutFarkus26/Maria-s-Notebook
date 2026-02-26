// GroupProgressionViewModel.swift
// ViewModel for the group progression matrix.

import Foundation
import SwiftData
import OSLog

/// Builds the student × lesson matrix for a single subject/group.
@Observable
@MainActor
final class GroupProgressionViewModel {
    private static let logger = Logger.app_

    // MARK: - Published State

    private(set) var lessons: [Lesson] = []
    var students: [Student] = []
    var matrix: [UUID: [UUID: GroupCellStatus]] = [:]  // [studentID: [lessonID: status]]
    private(set) var isLoading = false

    /// Students clustered by readiness
    private(set) var readyForNext: [Student] = []
    private(set) var practicing: [Student] = []
    private(set) var needsAttention: [Student] = []

    /// Students not in any readiness cluster
    var unclustered: [Student] {
        let clusteredIDs = Set(readyForNext.map(\.id) + practicing.map(\.id) + needsAttention.map(\.id))
        return students.filter { !clusteredIDs.contains($0.id) }
    }

    /// Selected students for batch actions
    var selectedStudentIDs: Set<UUID> = []

    // Keep references for batch actions
    private var allLessons: [Lesson] = []
    private var allPresentations: [LessonAssignment] = []
    private var allStudents: [Student] = []

    // MARK: - Configuration

    func configure(subject: String, group: String, context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        let fetchedLessons = fetchAllLessons(context: context)
        let fetchedPresentations = fetchPresentations(context: context)
        let fetchedWork = fetchAllWork(context: context)
        let fetchedStudents = fetchStudents(context: context)

        allLessons = fetchedLessons
        allPresentations = fetchedPresentations
        allStudents = fetchedStudents

        // Filter lessons in this group, sorted by orderInGroup
        let groupLessons = fetchedLessons
            .filter { $0.subject.trimmed() == subject && $0.group.trimmed() == group }
            .sorted { $0.orderInGroup < $1.orderInGroup }
        lessons = groupLessons

        // Filter visible students
        let visibleStudents = TestStudentsFilter.filterVisible(fetchedStudents)
        let visibleStudentMap = Dictionary(uniqueKeysWithValues: visibleStudents.map { ($0.id, $0) })

        // Pre-index presentations and work by lessonID for O(1) lookups
        let presentationsByLesson = Dictionary(grouping: fetchedPresentations) { $0.lessonID }
        let workByLesson = Dictionary(grouping: fetchedWork) { $0.lessonID }

        // Find presentations and work within this group using pre-indexed dictionaries
        var groupPresentations: [LessonAssignment] = []
        var groupWork: [WorkModel] = []
        for lesson in groupLessons {
            let lid = lesson.id.uuidString
            if let pres = presentationsByLesson[lid] { groupPresentations.append(contentsOf: pres) }
            if let work = workByLesson[lid] { groupWork.append(contentsOf: work) }
        }

        var activeStudentIDs = Set<UUID>()
        for la in groupPresentations {
            for sidStr in la.studentIDs {
                if let sid = UUID(uuidString: sidStr), visibleStudentMap[sid] != nil {
                    activeStudentIDs.insert(sid)
                }
            }
        }
        for w in groupWork {
            if let sid = UUID(uuidString: w.studentID), visibleStudentMap[sid] != nil {
                activeStudentIDs.insert(sid)
            }
        }

        let groupStudents = activeStudentIDs.compactMap { visibleStudentMap[$0] }
            .sorted { $0.fullName < $1.fullName }
        students = groupStudents

        // Pre-index group work by studentID for O(1) lookups per student
        let groupWorkByStudent = Dictionary(grouping: groupWork) { $0.studentID }

        // Build matrix
        var matrixResult: [UUID: [UUID: GroupCellStatus]] = [:]
        var readyList: [Student] = []
        var practicingList: [Student] = []
        var attentionList: [Student] = []

        let staleThreshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        for student in groupStudents {
            let studentIDStr = student.id.uuidString
            let studentPresentations = groupPresentations.filter { $0.studentIDs.contains(studentIDStr) }
            let studentWork = groupWorkByStudent[studentIDStr] ?? []
            var studentRow: [UUID: GroupCellStatus] = [:]

            var furthestPresentedOrder = -1
            var hasActiveWork = false
            var hasStaleWork = false

            for lesson in groupLessons {
                let lessonIDStr = lesson.id.uuidString

                // Check presentation status
                let presented = studentPresentations.contains { $0.lessonID == lessonIDStr && $0.presentedAt != nil }
                let scheduled = studentPresentations.contains { $0.lessonID == lessonIDStr && $0.isScheduled }

                // Check work status
                let lessonWork = studentWork.filter { $0.lessonID == lessonIDStr }
                let activeWork = lessonWork.filter { $0.status != .complete }
                let reviewWork = lessonWork.filter { $0.status == .review }
                let allWorkComplete = !lessonWork.isEmpty && lessonWork.allSatisfy { $0.status == .complete }

                // Determine cell status
                let status: GroupCellStatus
                if presented {
                    furthestPresentedOrder = max(furthestPresentedOrder, lesson.orderInGroup)
                    if allWorkComplete {
                        status = .mastered
                    } else if !reviewWork.isEmpty {
                        status = .workReview
                        hasActiveWork = true
                    } else if !activeWork.isEmpty {
                        status = .workActive
                        hasActiveWork = true
                        if activeWork.contains(where: { ($0.lastTouchedAt ?? $0.createdAt) < staleThreshold }) {
                            hasStaleWork = true
                        }
                    } else {
                        status = .presented
                    }
                } else if scheduled {
                    status = .scheduled
                } else {
                    status = .notStarted
                }

                studentRow[lesson.id] = status
            }

            matrixResult[student.id] = studentRow

            // Cluster student
            if hasStaleWork {
                attentionList.append(student)
            } else if hasActiveWork {
                practicingList.append(student)
            } else if furthestPresentedOrder >= 0 {
                readyList.append(student)
            }
        }

        matrix = matrixResult
        readyForNext = readyList
        practicing = practicingList
        needsAttention = attentionList
    }

    // MARK: - Batch Actions

    func scheduleNextLesson(context: ModelContext) {
        guard !selectedStudentIDs.isEmpty, !lessons.isEmpty else { return }

        for studentID in selectedStudentIDs {
            let studentIDStr = studentID.uuidString
            let studentPresentations = allPresentations.filter {
                $0.studentIDs.contains(studentIDStr) && $0.presentedAt != nil
            }

            var furthestLesson: Lesson?
            var furthestOrder = -1
            for lesson in lessons {
                let presented = studentPresentations.contains { $0.lessonID == lesson.id.uuidString }
                if presented && lesson.orderInGroup > furthestOrder {
                    furthestOrder = lesson.orderInGroup
                    furthestLesson = lesson
                }
            }

            guard let current = furthestLesson else { continue }
            guard let nextLesson = PlanNextLessonService.findNextLesson(after: current, in: allLessons) else { continue }

            PlanNextLessonService.planLesson(
                nextLesson,
                forStudents: [studentID],
                allStudents: allStudents,
                allLessons: allLessons,
                existingLessonAssignments: allPresentations,
                context: context
            )
        }

        context.safeSave()
        selectedStudentIDs.removeAll()
    }

    // MARK: - Add Students

    func availableStudents() -> [Student] {
        let existingIDs = Set(students.map { $0.id })
        let visible = TestStudentsFilter.filterVisible(allStudents)
        return visible.filter { !existingIDs.contains($0.id) }.sorted { $0.fullName < $1.fullName }
    }

    func addStudent(_ student: Student) {
        students.append(student)
        matrix[student.id] = Dictionary(
            uniqueKeysWithValues: lessons.map { ($0.id, GroupCellStatus.notStarted) }
        )
    }

    // MARK: - Fetching

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

    private func fetchStudents(context: ModelContext) -> [Student] {
        let descriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        return context.safeFetch(descriptor)
    }
}
