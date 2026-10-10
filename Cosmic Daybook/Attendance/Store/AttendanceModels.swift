import Foundation
import SwiftUI

// MARK: - Attendance Status

/// Stored by raw value and read on every device, some of them on older
/// builds (a TestFlight phone can't be made to update with the Mac). An
/// unknown value reads as `.unmarked`, so a new case must never be a mark an
/// older build could overwrite: `markUnmarkedAbsent` skips unknown values.
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
        case .tardy: return "Late"
        case .leftEarly: return "Left Early"
        }
    }

    /// The word Siri says for a mark, in a sentence: the tiles' words, so a
    /// tardy mark is "late" ("Maya is marked late").
    nonisolated var spokenWord: String {
        switch self {
        case .unmarked: return "unmarked"
        case .present: return "present"
        case .absent: return "absent"
        case .tardy: return "late"
        case .leftEarly: return "as left early"
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
}

// MARK: - Absence Reason

/// Why a child is absent. Stored by raw value on the shared record; a build
/// that doesn't know a reason reads it as `.none` (and can write that back),
/// so every device takes a new reason in the same roll-out.
enum AbsenceReason: String, Codable, CaseIterable, Sendable {
    case none
    case sick
    case vacation
    case appointment
    case family
    /// Anything else; the day's note says what.
    case other

    /// Every reason a guide can give, without `.none`.
    static let given: [AbsenceReason] = allCases.filter { $0 != .none }

    var displayName: String {
        switch self {
        case .none: return ""
        case .sick: return "Sick"
        case .vacation: return "Vacation"
        case .appointment: return "Appointment"
        case .family: return "Family"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle" // Placeholder - shouldn't be displayed when .none, but prevents SF Symbol error
        case .sick: return "cross.case.fill"
        case .vacation: return "beach.umbrella.fill"
        case .appointment: return "calendar.badge.clock"
        case .family: return "figure.2.and.child.holdinghands"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Date Normalization Helper

nonisolated extension Date {
    /// Returns the start of the day for this date using the provided calendar (default .current).
    func normalizedDay(using calendar: Calendar = .current) -> Date {
        return calendar.startOfDay(for: self)
    }
}
