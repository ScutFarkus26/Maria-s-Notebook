// LessonFrequencyViewModel.swift
// ViewModel for the CDLesson Frequency Dashboard — loads per-student weekly lesson counts
// and highlights students below the AMI target of 5–7 lessons per week.

import Foundation
import CoreData
import OSLog

@Observable
@MainActor
final class LessonFrequencyViewModel {
    private static let logger = Logger.app_

    // MARK: - Outputs

    private(set) var studentCards: [StudentFrequencyCard] = []
    private(set) var isLoading = false

    // MARK: - Filters

    var searchText: String = ""
    var levelFilter: LevelFilter = .all
    var selectedWeekOffset: Int = 0   // 0 = current week, -1 = last week, etc.
    let targetRange: ClosedRange<Int> = 5...7  // AMI default

    // MARK: - Computed Outputs

    var filteredCards: [StudentFrequencyCard] {
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

        // Sort: below-target first, then by count ascending (lowest first)
        return cards.sorted { lhs, rhs in
            let lhsStatus = FrequencyStatus.from(count: lhs.lessonCount, target: targetRange)
            let rhsStatus = FrequencyStatus.from(count: rhs.lessonCount, target: targetRange)
            let lhsOrder = statusSortOrder(lhsStatus)
            let rhsOrder = statusSortOrder(rhsStatus)
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if lhs.lessonCount != rhs.lessonCount { return lhs.lessonCount < rhs.lessonCount }
            return lhs.firstName < rhs.firstName
        }
    }

    var weekLabel: String {
        let date = LessonAnalyticsService.dateForWeekOffset(selectedWeekOffset)
        return LessonAnalyticsService.weekLabel(for: date)
    }

    var classAverage: Double {
        let cards = filteredCards
        guard !cards.isEmpty else { return 0 }
        let total = cards.reduce(0) { $0 + $1.lessonCount }
        return Double(total) / Double(cards.count)
    }

    var belowTargetCount: Int {
        filteredCards.filter { $0.lessonCount < targetRange.lowerBound }.count
    }

    var onTargetCount: Int {
        filteredCards.filter {
            $0.lessonCount >= targetRange.lowerBound && $0.lessonCount <= targetRange.upperBound
        }.count
    }

    var totalLessonsThisWeek: Int {
        filteredCards.reduce(0) { $0 + $1.lessonCount }
    }

    // MARK: - Data Loading

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        // 1. Compute week range from selectedWeekOffset
        let referenceDate = LessonAnalyticsService.dateForWeekOffset(selectedWeekOffset)
        let (weekStart, weekEnd) = LessonAnalyticsService.schoolWeekRange(for: referenceDate)

        // 2. Fetch presented records for the week
        let records = LessonAnalyticsService.fetchPresentedRecords(
            context: context,
            from: weekStart,
            to: weekEnd
        )

        // 3. Fetch all students, filter visible
        let studentRequest: NSFetchRequest<CDStudent> = CDFetchRequest()
        studentRequest.sortDescriptors = CDStudent.sortByName
        let allStudents = context.safeFetch(studentRequest).filter(\.isEnrolled)
        let visibleStudents = TestStudentsFilter.filterVisible(allStudents)

        // 4. Group records by studentID
        let recordsByStudent = Dictionary(grouping: records) { $0.studentID }

        // 5. Build cards — include students with 0 lessons
        var cards: [StudentFrequencyCard] = []
        for student in visibleStudents {
            let studentID = student.id ?? UUID()
            let studentRecords = recordsByStudent[studentID.uuidString] ?? []
            let subjectGroups = Dictionary(grouping: studentRecords) { $0.subject }
            let breakdown = subjectGroups.map {
                SubjectCount(subject: $0.key, count: $0.value.count)
            }.sorted { $0.count > $1.count }

            cards.append(StudentFrequencyCard(
                id: studentID,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                lessonCount: studentRecords.count,
                subjectBreakdown: breakdown
            ))
        }

        studentCards = cards
    }

    // MARK: - Helpers

    private func statusSortOrder(_ status: FrequencyStatus) -> Int {
        switch status {
        case .belowTarget: return 0
        case .onTarget: return 1
        case .aboveTarget: return 2
        }
    }
}
