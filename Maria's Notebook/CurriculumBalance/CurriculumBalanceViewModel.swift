// CurriculumBalanceViewModel.swift
// ViewModel for Curriculum Balance Analytics — computes subject distribution,
// weekly trends, gap analysis, and per-student breakdowns.

import Foundation
import SwiftData
import SwiftUI
import OSLog

@Observable
@MainActor
final class CurriculumBalanceViewModel {
    private static let logger = Logger.app_

    // MARK: - Outputs

    private(set) var classroomDistribution: [SubjectDistribution] = []
    private(set) var weeklyTrends: [SubjectWeeklyTrend] = []
    private(set) var classroomGaps: [SubjectGap] = []
    private(set) var studentCards: [StudentBalanceCard] = []
    private(set) var isLoading = false

    // MARK: - Filters

    var searchText: String = ""
    var levelFilter: LevelFilter = .all
    var timeRange: AnalyticsTimeRange = .month
    var scope: AnalyticsScope = .classroom

    // MARK: - Computed

    var filteredStudentCards: [StudentBalanceCard] {
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

    var totalLessons: Int {
        classroomDistribution.reduce(0) { $0 + $1.count }
    }

    var uniqueSubjectCount: Int {
        classroomDistribution.count
    }

    // MARK: - Data Loading

    // swiftlint:disable:next function_body_length
    func loadData(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        let (start, end) = timeRange.dateRange(from: Date())
        let records = LessonAnalyticsService.fetchPresentedRecords(
            context: context,
            from: start,
            to: end
        )

        // --- Classroom-wide distribution ---
        let bySubject = Dictionary(grouping: records) { $0.subject }
        let total = max(records.count, 1)
        classroomDistribution = bySubject.map { subject, recs in
            SubjectDistribution(
                subject: subject,
                count: recs.count,
                percentage: Double(recs.count) / Double(total),
                color: AppColors.color(forSubject: subject)
            )
        }.sorted { $0.count > $1.count }

        // --- Weekly trends ---
        weeklyTrends = computeWeeklyTrends(records: records)

        // --- Gap analysis ---
        let avgCount = Double(total) / Double(max(bySubject.count, 1))
        classroomGaps = classroomDistribution
            .filter { Double($0.count) < avgCount * 0.5 }  // below 50% of average
            .map { dist in
                SubjectGap(
                    subject: dist.subject,
                    count: dist.count,
                    classAverage: avgCount,
                    deficit: avgCount - Double(dist.count),
                    color: dist.color
                )
            }
            .sorted { $0.deficit > $1.deficit }

        // --- Per-student cards ---
        let allStudents = context.safeFetch(
            FetchDescriptor<Student>(sortBy: Student.sortByName)
        )
        let visibleStudents = TestStudentsFilter.filterVisible(allStudents)
        let recordsByStudent = Dictionary(grouping: records) { $0.studentID }

        studentCards = visibleStudents.compactMap { student in
            let recs = recordsByStudent[student.id.uuidString] ?? []
            guard !recs.isEmpty else { return nil }

            let perSubject = Dictionary(grouping: recs) { $0.subject }
            let studentTotal = max(recs.count, 1)

            let dists = perSubject.map { subject, sRecs in
                SubjectDistribution(
                    subject: subject,
                    count: sRecs.count,
                    percentage: Double(sRecs.count) / Double(studentTotal),
                    color: AppColors.color(forSubject: subject)
                )
            }.sorted { $0.count > $1.count }

            // Student-level gaps
            let studentAvg = Double(studentTotal) / Double(max(perSubject.count, 1))
            let gaps = dists
                .filter { Double($0.count) < studentAvg * 0.5 }
                .map {
                    SubjectGap(
                        subject: $0.subject,
                        count: $0.count,
                        classAverage: studentAvg,
                        deficit: studentAvg - Double($0.count),
                        color: $0.color
                    )
                }

            return StudentBalanceCard(
                id: student.id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                totalLessons: recs.count,
                subjectCounts: dists,
                gaps: gaps
            )
        }
    }

    // MARK: - Weekly Trends Computation

    private func computeWeeklyTrends(records: [LessonAnalyticsService.PresentedRecord]) -> [SubjectWeeklyTrend] {
        let cal = AppCalendar.shared

        // Group records by (subject, weekStart)
        var grouped: [String: [Date: Int]] = [:]
        for record in records {
            let (weekStart, _) = LessonAnalyticsService.schoolWeekRange(for: record.presentedAt)
            grouped[record.subject, default: [:]][weekStart, default: 0] += 1
        }

        // Flatten into array
        var trends: [SubjectWeeklyTrend] = []
        for (subject, weekCounts) in grouped {
            let color = AppColors.color(forSubject: subject)
            for (weekStart, count) in weekCounts {
                trends.append(SubjectWeeklyTrend(
                    subject: subject,
                    weekStart: weekStart,
                    count: count,
                    color: color
                ))
            }
        }

        // Sort by weekStart then subject for consistent chart rendering
        return trends.sorted {
            if $0.weekStart != $1.weekStart { return $0.weekStart < $1.weekStart }
            return $0.subject < $1.subject
        }
    }
}
