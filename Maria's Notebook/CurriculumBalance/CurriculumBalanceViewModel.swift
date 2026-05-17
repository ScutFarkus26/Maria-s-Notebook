// CurriculumBalanceViewModel.swift
// ViewModel for Curriculum Balance Analytics — computes area distribution,
// weekly trends, gap analysis, and per-student breakdowns.

import Foundation
import CoreData
import SwiftUI
import OSLog

@Observable
@MainActor
final class CurriculumBalanceViewModel {
    private static let logger = Logger.app_

    // MARK: - Outputs

    private(set) var classroomDistribution: [AreaDistribution] = []
    private(set) var weeklyTrends: [AreaWeeklyTrend] = []
    private(set) var classroomGaps: [AreaGap] = []
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

    var uniqueAreaCount: Int {
        classroomDistribution.count
    }

    // MARK: - Data Loading

    // swiftlint:disable:next function_body_length
    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let (start, end) = timeRange.dateRange(from: Date())
        let records = LessonAnalyticsService.fetchPresentedRecords(
            context: context,
            from: start,
            to: end
        )

        // --- Classroom-wide distribution ---
        let byArea = Dictionary(grouping: records) { $0.area }
        let total = max(records.count, 1)
        classroomDistribution = byArea.map { area, recs in
            AreaDistribution(
                area: area,
                count: recs.count,
                percentage: Double(recs.count) / Double(total),
                color: AppColors.color(forArea: area)
            )
        }.sorted { $0.count > $1.count }

        // --- Weekly trends ---
        weeklyTrends = computeWeeklyTrends(records: records)

        // --- Gap analysis ---
        let avgCount = Double(total) / Double(max(byArea.count, 1))
        classroomGaps = classroomDistribution
            .filter { Double($0.count) < avgCount * 0.5 }  // below 50% of average
            .map { dist in
                AreaGap(
                    area: dist.area,
                    count: dist.count,
                    classAverage: avgCount,
                    deficit: avgCount - Double(dist.count),
                    color: dist.color
                )
            }
            .sorted { $0.deficit > $1.deficit }

        // --- Per-student cards ---
        let studentRequest: NSFetchRequest<CDStudent> = CDFetchRequest(CDStudent.self)
        studentRequest.sortDescriptors = CDStudent.sortByName
        let allStudents = context.safeFetch(studentRequest)
        let visibleStudents = TestStudentsFilter.filterVisible(allStudents.filterEnrolled())
        let recordsByStudent = Dictionary(grouping: records) { $0.studentID }

        studentCards = visibleStudents.compactMap { student in
            guard let studentID = student.id else { return nil }
            let recs = recordsByStudent[studentID.uuidString] ?? []
            guard !recs.isEmpty else { return nil }

            let perArea = Dictionary(grouping: recs) { $0.area }
            let studentTotal = max(recs.count, 1)

            let dists = perArea.map { area, sRecs in
                AreaDistribution(
                    area: area,
                    count: sRecs.count,
                    percentage: Double(sRecs.count) / Double(studentTotal),
                    color: AppColors.color(forArea: area)
                )
            }.sorted { $0.count > $1.count }

            // CDStudent-level gaps
            let studentAvg = Double(studentTotal) / Double(max(perArea.count, 1))
            let gaps = dists
                .filter { Double($0.count) < studentAvg * 0.5 }
                .map {
                    AreaGap(
                        area: $0.area,
                        count: $0.count,
                        classAverage: studentAvg,
                        deficit: studentAvg - Double($0.count),
                        color: $0.color
                    )
                }

            return StudentBalanceCard(
                id: studentID,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                totalLessons: recs.count,
                areaCounts: dists,
                gaps: gaps
            )
        }
    }

    // MARK: - Weekly Trends Computation

    private func computeWeeklyTrends(records: [LessonAnalyticsService.PresentedRecord]) -> [AreaWeeklyTrend] {
        // Group records by (area, weekStart)
        var grouped: [String: [Date: Int]] = [:]
        for record in records {
            let (weekStart, _) = LessonAnalyticsService.schoolWeekRange(for: record.presentedAt)
            grouped[record.area, default: [:]][weekStart, default: 0] += 1
        }

        // Flatten into array
        var trends: [AreaWeeklyTrend] = []
        for (area, weekCounts) in grouped {
            let color = AppColors.color(forArea: area)
            for (weekStart, count) in weekCounts {
                trends.append(AreaWeeklyTrend(
                    area: area,
                    weekStart: weekStart,
                    count: count,
                    color: color
                ))
            }
        }

        // Sort by weekStart then area for consistent chart rendering
        return trends.sorted {
            if $0.weekStart != $1.weekStart { return $0.weekStart < $1.weekStart }
            return $0.area < $1.area
        }
    }
}
