// CurriculumBalanceTypes.swift
// Value types for the Curriculum Balance Analytics view.
// Tracks subject distribution, weekly trends, and gap analysis.

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
    case perStudent = "Per CDStudent"

    var id: String { rawValue }
}

/// Subject distribution data point for charts.
struct SubjectDistribution: Identifiable {
    var id: String { subject }
    let subject: String
    let count: Int
    let percentage: Double  // 0.0 ... 1.0
    let color: Color
}

/// Weekly trend data point for a subject.
struct SubjectWeeklyTrend: Identifiable {
    var id: String { "\(subject)|\(Int(weekStart.timeIntervalSince1970))" }
    let subject: String
    let weekStart: Date
    let count: Int
    let color: Color
}

/// Gap analysis entry — subject with notably low representation.
struct SubjectGap: Identifiable {
    var id: String { subject }
    let subject: String
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
    let subjectCounts: [SubjectDistribution]
    let gaps: [SubjectGap]

    var displayName: String { nickname ?? firstName }
}
