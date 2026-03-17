// ProgressDashboardViewModel.swift
// ViewModel for the Progress Dashboard — loads per-student, per-category progress.

import Foundation
import SwiftData
import OSLog

@Observable
@MainActor
final class ProgressDashboardViewModel {
    private static let logger = Logger.app_

    // MARK: - Outputs

    private(set) var studentCards: [StudentDashboardCard] = []
    private(set) var isLoading = false

    // Lookup for sheet navigation
    private(set) var lessonAssignmentsByID: [UUID: LessonAssignment] = [:]

    // MARK: - Filters

    var searchText: String = ""
    var levelFilter: LevelFilter = .all

    var filteredCards: [StudentDashboardCard] {
        var cards = studentCards

        if levelFilter != .all {
            cards = cards.filter { levelFilter.matches($0.level) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            cards = cards.filter { card in
                card.firstName.lowercased().contains(query) ||
                card.lastName.lowercased().contains(query) ||
                (card.nickname?.lowercased().contains(query) ?? false)
            }
        }

        return cards
    }

    // MARK: - Data Loading

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func loadData(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        let allStudents = fetchAllStudents(context: context)
        let allLessons = fetchAllLessons(context: context)
        let allAssignments = fetchAllAssignments(context: context)
        let allWork = fetchAllWork(context: context)

        let visibleStudents = TestStudentsFilter.filterVisible(allStudents)
        let today = Date()

        // Pre-index for O(1) lookups
        let lessonsByID: [UUID: Lesson] = Dictionary(
            uniqueKeysWithValues: allLessons.map { ($0.id, $0) }
        )

        // Index assignments by lessonID
        let assignmentsByLesson = Dictionary(grouping: allAssignments) { $0.lessonID }

        // Group lessons by subject+group
        let lessonsBySubjectGroup = Dictionary(grouping: allLessons) {
            SubjectGroupKey(subject: $0.subject.trimmed().lowercased(), group: $0.group.trimmed().lowercased())
        }

        // Index open work by studentID+lessonID
        let openWork = allWork.filter { $0.status != .complete }
        let openWorkByStudentLesson = Dictionary(grouping: openWork) {
            "\($0.studentID)|\($0.lessonID)"
        }

        // Build lessonAssignmentsByID for sheet navigation
        var assignmentLookup: [UUID: LessonAssignment] = [:]
        for la in allAssignments {
            assignmentLookup[la.id] = la
        }
        lessonAssignmentsByID = assignmentLookup

        // Build cards
        var cards: [StudentDashboardCard] = []

        for student in visibleStudents {
            let studentIDStr = student.id.uuidString

            // Find all (subject, group) pairs where this student has a presented assignment
            var activePairs = Set<SubjectGroupKey>()
            for la in allAssignments where la.presentedAt != nil {
                guard la.studentIDs.contains(studentIDStr) else { continue }
                guard let lesson = lessonsByID[la.lessonIDUUID ?? UUID()] else { continue }
                let key = SubjectGroupKey(
                    subject: lesson.subject.trimmed().lowercased(),
                    group: lesson.group.trimmed().lowercased()
                )
                guard !key.subject.isEmpty, !key.group.isEmpty else { continue }
                activePairs.insert(key)
            }

            // Also include pairs where student has a draft/scheduled assignment (not yet presented)
            for la in allAssignments where la.presentedAt == nil {
                guard la.studentIDs.contains(studentIDStr) else { continue }
                guard let lesson = lessonsByID[la.lessonIDUUID ?? UUID()] else { continue }
                let key = SubjectGroupKey(
                    subject: lesson.subject.trimmed().lowercased(),
                    group: lesson.group.trimmed().lowercased()
                )
                guard !key.subject.isEmpty, !key.group.isEmpty else { continue }
                activePairs.insert(key)
            }

            guard !activePairs.isEmpty else { continue }

            var categoryRows: [StudentCategoryProgress] = []

            for pairKey in activePairs {
                guard let lessonsInGroup = lessonsBySubjectGroup[pairKey] else { continue }
                let sortedLessons = lessonsInGroup.sorted { $0.orderInGroup < $1.orderInGroup }

                // Find the most recently presented lesson for this student in this group
                var bestPresentedLesson: Lesson?
                var bestPresentedAt: Date?
                var bestAssignmentID: UUID?

                for lesson in sortedLessons {
                    guard let assignments = assignmentsByLesson[lesson.id.uuidString] else { continue }
                    for la in assignments where la.presentedAt != nil {
                        guard la.studentIDs.contains(studentIDStr) else { continue }
                        if bestPresentedAt == nil || la.presentedAt! > bestPresentedAt! {
                            bestPresentedLesson = lesson
                            bestPresentedAt = la.presentedAt
                            bestAssignmentID = la.id
                        }
                    }
                }

                let previousLesson: PreviousLessonSummary?
                if let lesson = bestPresentedLesson, let at = bestPresentedAt, let aID = bestAssignmentID {
                    previousLesson = PreviousLessonSummary(
                        id: aID,
                        lessonID: lesson.id,
                        name: lesson.name,
                        presentedAt: at,
                        assignmentID: aID
                    )
                } else {
                    previousLesson = nil
                }

                // Collect open work for this student in this group's lessons
                var workSummaries: [OpenWorkSummary] = []
                for lesson in sortedLessons {
                    let key = "\(studentIDStr)|\(lesson.id.uuidString)"
                    guard let workItems = openWorkByStudentLesson[key] else { continue }
                    for work in workItems {
                        let age = Self.weekdaysBetween(from: work.assignedAt, to: today)
                        workSummaries.append(OpenWorkSummary(
                            id: work.id,
                            title: work.title,
                            kind: work.kind,
                            status: work.status,
                            ageSchoolDays: age
                        ))
                    }
                }

                // Find next lesson
                let nextLessonInfo: NextLessonInfo?
                if let prevLesson = bestPresentedLesson {
                    if let nextLesson = PlanNextLessonService.findNextLesson(after: prevLesson, in: allLessons) {
                        let nextInfo = Self.resolveNextLessonState(
                            lesson: nextLesson,
                            studentIDStr: studentIDStr,
                            assignmentsByLesson: assignmentsByLesson
                        )
                        nextLessonInfo = nextInfo
                    } else {
                        nextLessonInfo = nil
                    }
                } else {
                    // No presented lesson yet — check if there's a draft/scheduled for the first lesson
                    if let firstLesson = sortedLessons.first {
                        let nextInfo = Self.resolveNextLessonState(
                            lesson: firstLesson,
                            studentIDStr: studentIDStr,
                            assignmentsByLesson: assignmentsByLesson
                        )
                        nextLessonInfo = nextInfo
                    } else {
                        nextLessonInfo = nil
                    }
                }

                // Use the original casing from the first lesson in the group for display
                let displaySubject = sortedLessons.first?.subject.trimmed() ?? pairKey.subject
                let displayGroup = sortedLessons.first?.group.trimmed() ?? pairKey.group

                categoryRows.append(StudentCategoryProgress(
                    id: "\(student.id)|\(displaySubject)|\(displayGroup)",
                    subject: displaySubject,
                    group: displayGroup,
                    previousLesson: previousLesson,
                    openWork: workSummaries,
                    nextLesson: nextLessonInfo
                ))
            }

            // Sort categories: by subject then group
            categoryRows.sort { ($0.subject, $0.group) < ($1.subject, $1.group) }

            cards.append(StudentDashboardCard(
                id: student.id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                categories: categoryRows
            ))
        }

        studentCards = cards
    }

    // MARK: - Helpers

    private static func resolveNextLessonState(
        lesson: Lesson,
        studentIDStr: String,
        assignmentsByLesson: [String: [LessonAssignment]]
    ) -> NextLessonInfo {
        let lessonIDStr = lesson.id.uuidString
        var state: NextLessonState = .notPlanned
        var assignmentID: UUID?

        if let assignments = assignmentsByLesson[lessonIDStr] {
            for la in assignments where la.presentedAt == nil {
                guard la.studentIDs.contains(studentIDStr) else { continue }
                if let scheduledDate = la.scheduledFor {
                    state = .scheduled(scheduledDate)
                    assignmentID = la.id
                    break
                } else {
                    state = .inInbox
                    assignmentID = la.id
                }
            }
        }

        return NextLessonInfo(
            id: lesson.id,
            name: lesson.name,
            state: state,
            assignmentID: assignmentID
        )
    }

    /// Count weekdays between two dates (simple school-day approximation).
    private static func weekdaysBetween(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay < endDay else { return 0 }

        var count = 0
        var current = startDay
        while current < endDay {
            let weekday = calendar.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 { // Not Sunday or Saturday
                count += 1
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return count
    }

    // MARK: - Fetching

    private func fetchAllStudents(context: ModelContext) -> [Student] {
        context.safeFetch(FetchDescriptor<Student>(sortBy: Student.sortByName)).filter { $0.isEnrolled }
    }

    private func fetchAllLessons(context: ModelContext) -> [Lesson] {
        context.safeFetch(FetchDescriptor<Lesson>(sortBy: [
            SortDescriptor(\Lesson.subject),
            SortDescriptor(\Lesson.group),
            SortDescriptor(\Lesson.orderInGroup)
        ]))
    }

    private func fetchAllAssignments(context: ModelContext) -> [LessonAssignment] {
        context.safeFetch(FetchDescriptor<LessonAssignment>())
    }

    private func fetchAllWork(context: ModelContext) -> [WorkModel] {
        context.safeFetch(FetchDescriptor<WorkModel>())
    }
}

// MARK: - Internal Key

private struct SubjectGroupKey: Hashable {
    let subject: String
    let group: String
}
