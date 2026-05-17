// CurriculumBalanceTypes.swift
// Value types for the Curriculum Balance Analytics view.
// Tracks area distribution, weekly trends, and gap analysis.

import Foundation
import SwiftUI

/// Time range options for the analytics view.
enum AnalyticsTimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var id: String { rawValue }

    /// Returns (start, exclusiveEnd) date range ending at `date`.
    func dateRange(from date: Date) -> (start: Date, end: Date) {
        let cal = AppCalendar.shared
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))!
        let start: Date
        switch self {
        case .week:
            start = cal.date(byAdding: .day, value: -7, to: endOfDay)!
        case .month:
            start = cal.date(byAdding: .month, value: -1, to: endOfDay)!
        case .quarter:
            start = cal.date(byAdding: .month, value: -3, to: endOfDay)!
        case .year:
            start = cal.date(byAdding: .year, value: -1, to: endOfDay)!
        }
        return (start, endOfDay)
    }
}

/// View scope: classroom-wide vs per-student drill-down.
enum AnalyticsScope: String, CaseIterable, Identifiable {
    case classroom = "Classroom"
    case perStudent = "Per Student"

    var id: String { rawValue }
}

/// Area distribution data point for charts.
struct AreaDistribution: Identifiable {
    var id: String { area }
    let area: String
    let count: Int
    let percentage: Double  // 0.0 ... 1.0
    let color: Color
}

/// Weekly trend data point for a area.
struct AreaWeeklyTrend: Identifiable {
    var id: String { "\(area)|\(Int(weekStart.timeIntervalSince1970))" }
    let area: String
    let weekStart: Date
    let count: Int
    let color: Color
}

/// Gap analysis entry — area with notably low representation.
struct AreaGap: Identifiable {
    var id: String { area }
    let area: String
    let count: Int
    let classAverage: Double
    let deficit: Double  // how far below average (positive = gap)
    let color: Color
}

/// Per-student balance summary card.
struct StudentBalanceCard: Identifiable {
    let id: UUID                  // student.id
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let totalLessons: Int
    let areaCounts: [AreaDistribution]
    let gaps: [AreaGap]

    var displayName: String { nickname ?? firstName }
}
