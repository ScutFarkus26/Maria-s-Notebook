import Foundation
import SwiftUI

// MARK: - Attendance Status

enum AttendanceStatus: String, Codable, CaseIterable, Sendable {
    case unmarked
    case present
    case absent
    case tardy
    case leftEarly

    var displayName: String {
        switch self {
        case .unmarked: return "Unmarked"
        case .present: return "Present"
        case .absent: return "Absent"
        case .tardy: return "Tardy"
        case .leftEarly: return "Left Early"
        }
    }

    var color: Color {
        switch self {
        case .unmarked: return Color.gray.opacity(UIConstants.OpacityConstants.quarter)
        case .present: return Color.green.opacity(UIConstants.OpacityConstants.statusBg)
        case .absent: return Color.red.opacity(UIConstants.OpacityConstants.statusBg)
        case .tardy: return Color.blue.opacity(UIConstants.OpacityConstants.statusBg)
        case .leftEarly: return Color.purple.opacity(UIConstants.OpacityConstants.statusBg)
        }
    }

    /// Returns the next status in the cycle: unmarked → present → absent → tardy → leftEarly → unmarked
    func next() -> AttendanceStatus {
        switch self {
        case .unmarked: return .present
        case .present: return .absent
        case .absent: return .tardy
        case .tardy: return .leftEarly
        case .leftEarly: return .unmarked
        }
    }
}

// MARK: - Absence Reason

enum AbsenceReason: String, Codable, CaseIterable, Sendable {
    case none
    case sick
    case vacation

    var displayName: String {
        switch self {
        case .none: return ""
        case .sick: return "Sick"
        case .vacation: return "Vacation"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle" // Placeholder - shouldn't be displayed when .none, but prevents SF Symbol error
        case .sick: return "cross.case.fill"
        case .vacation: return "beach.umbrella.fill"
        }
    }
}

// MARK: - Date Normalization Helper

extension Date {
    /// Returns the start of the day for this date using the provided calendar (default .current).
    func normalizedDay(using calendar: Calendar = .current) -> Date {
        return calendar.startOfDay(for: self)
    }
}
