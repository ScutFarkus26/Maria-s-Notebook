// ObservationTimeRange.swift
// The look-back window used by the developmental traits screen.

import Foundation

enum ObservationTimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var id: String { rawValue }

    func dateRange(from now: Date) -> (start: Date, end: Date) {
        let calendar = AppCalendar.shared
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .quarter:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (start, now)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return (start, now)
        }
    }
}
