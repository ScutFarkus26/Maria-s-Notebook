// ThreeYearCycleViewModel.swift
// ViewModel for the Three-Year Cycle Bird's-Eye View — computes per-student cycle positioning and pace.

import SwiftUI
import CoreData

@Observable @MainActor
final class ThreeYearCycleViewModel {
    private(set) var studentCards: [CycleStudentCard] = []
    private(set) var isLoading = false

    var yearFilter: CycleYear?
    var levelFilter: LevelFilter = .all
    var searchText: String = ""
    var sortOrder: CycleSortOrder = .name

    // MARK: - Filtered Cards

    var filteredCards: [CycleStudentCard] {
        var cards = studentCards

        if let year = yearFilter {
            cards = cards.filter { $0.cycleYear == year }
        }

        if levelFilter != .all {
            cards = cards.filter { levelFilter.matches($0.level) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            cards = cards.filter {
                $0.firstName.lowercased().contains(query) ||
                $0.lastName.lowercased().contains(query) ||
                ($0.nickname?.lowercased().contains(query) ?? false)
            }
        }

        switch sortOrder {
        case .name:
            cards.sort { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
        case .pace:
            cards.sort { paceOrder($0.paceIndicator) < paceOrder($1.paceIndicator) }
        case .coverage:
            cards.sort { $0.coveragePercentage < $1.coveragePercentage }
        }

        return cards
    }

    // Summary stats
    var yearCounts: [CycleYear: Int] {
        var counts: [CycleYear: Int] = [:]
        for card in studentCards {
            counts[card.cycleYear, default: 0] += 1
        }
        return counts
    }

    var averageCoverage: Double {
        guard !studentCards.isEmpty else { return 0 }
        return studentCards.reduce(0.0) { $0 + $1.coveragePercentage } / Double(studentCards.count)
    }

    // MARK: - Load Data

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        // Fetch enrolled visible students
        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        studentRequest.sortDescriptors = CDStudent.sortByName
        let allStudents = TestStudentsFilter.filterVisible(context.safeFetch(studentRequest))

        // Fetch all lessons
        let lessonRequest = CDFetchRequest(CDLesson.self)
        let allLessons = context.safeFetch(lessonRequest)

        // Build lessons-by-subject index
        var lessonsBySubject: [String: [CDLesson]] = [:]
        var lessonIDSet: Set<String> = []
        for lesson in allLessons {
            guard let lid = lesson.id else { continue }
            lessonsBySubject[lesson.subject, default: []].append(lesson)
            lessonIDSet.insert(lid.uuidString)
        }
        let totalLessonsAvailable = allLessons.count

        // Fetch all presented assignments
        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        assignmentRequest.predicate = NSPredicate(
            format: "stateRaw == %@",
            LessonAssignmentState.presented.rawValue
        )
        let presentedAssignments = context.safeFetch(assignmentRequest)

        // Build student → presented lesson IDs index
        var presentedByStudent: [String: Set<String>] = [:]
        for assignment in presentedAssignments {
            let lessonID = assignment.lessonID
            guard lessonIDSet.contains(lessonID) else { continue }
            for studentIDStr in assignment.studentIDs {
                presentedByStudent[studentIDStr, default: []].insert(lessonID)
            }
        }

        // Build per-student cards
        let subjects = Array(lessonsBySubject.keys).sorted()

        studentCards = allStudents.compactMap { student in
            guard let sid = student.id else { return nil }
            let sidStr = sid.uuidString

            let cycleYear = CycleYear.calculate(from: student.dateStarted)
            let presentedLessonIDs = presentedByStudent[sidStr] ?? []
            let presentedCount = presentedLessonIDs.count
            let coveragePercentage = totalLessonsAvailable > 0
                ? Double(presentedCount) / Double(totalLessonsAvailable)
                : 0.0

            // Per-subject coverage
            let subjectCoverage: [SubjectCoverage] = subjects.compactMap { subject in
                guard let lessons = lessonsBySubject[subject] else { return nil }
                let total = lessons.count
                guard total > 0 else { return nil }
                let presented = lessons.filter { lesson in
                    guard let lid = lesson.id else { return false }
                    return presentedLessonIDs.contains(lid.uuidString)
                }.count
                return SubjectCoverage(
                    id: subject,
                    subject: subject,
                    presented: presented,
                    total: total,
                    percentage: Double(presented) / Double(total),
                    color: AppColors.color(forSubject: subject)
                )
            }

            let pace = PaceIndicator.calculate(
                coveragePercentage: coveragePercentage,
                cycleYear: cycleYear
            )

            return CycleStudentCard(
                id: sid,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                cycleYear: cycleYear,
                dateStarted: student.dateStarted,
                totalLessonsPresented: presentedCount,
                totalLessonsAvailable: totalLessonsAvailable,
                coveragePercentage: coveragePercentage,
                subjectCoverage: subjectCoverage,
                paceIndicator: pace
            )
        }
    }

    // MARK: - Helpers

    private func paceOrder(_ pace: PaceIndicator) -> Int {
        switch pace {
        case .farBehind: return 0
        case .behind: return 1
        case .onTrack: return 2
        case .ahead: return 3
        }
    }
}
