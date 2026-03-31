import Foundation
import SwiftUI

enum TodoMood: String, Codable, CaseIterable, Sendable {
    case energized = "Energized"
    case focused = "Focused"
    case stressed = "Stressed"
    case overwhelmed = "Overwhelmed"
    case satisfied = "Satisfied"
    case frustrated = "Frustrated"
    case motivated = "Motivated"
    case tired = "Tired"

    var emoji: String {
        switch self {
        case .energized: return "⚡️"
        case .focused: return "🎯"
        case .stressed: return "😰"
        case .overwhelmed: return "🤯"
        case .satisfied: return "😊"
        case .frustrated: return "😤"
        case .motivated: return "🔥"
        case .tired: return "😴"
        }
    }

    var color: Color {
        switch self {
        case .energized: return .yellow
        case .focused: return .blue
        case .stressed: return .orange
        case .overwhelmed: return .red
        case .satisfied: return .green
        case .frustrated: return .purple
        case .motivated: return .pink
        case .tired: return .gray
        }
    }
}

enum RecurrencePattern: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .none: return "calendar"
        case .daily: return "arrow.clockwise"
        case .weekdays: return "calendar.badge.clock"
        case .weekly: return "calendar.badge.clock"
        case .biweekly: return "calendar.badge.clock"
        case .monthly: return "calendar.badge.clock"
        case .yearly: return "calendar.badge.clock"
        case .custom: return "calendar.badge.clock"
        }
    }

    var description: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday (Mon-Fri)"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        case .custom: return "Custom interval"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return ""
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .biweekly: return "2 Weeks"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }

    /// Calculate the next due date based on the current due date
    /// For `.custom`, returns nil — handled externally using `customIntervalDays`.
    func nextDate(after date: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .none, .custom:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            // Find next weekday
            guard var nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            while calendar.isDateInWeekend(nextDate) {
                guard let next = calendar.date(byAdding: .day, value: 1, to: nextDate) else { return nil }
                nextDate = next
            }
            return nextDate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum TodoPriority: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var icon: String {
        switch self {
        case .none: return "circle"
        case .low: return "arrow.down.circle"
        case .medium: return "equal.circle"
        case .high: return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .none: return 3
        }
    }
}
