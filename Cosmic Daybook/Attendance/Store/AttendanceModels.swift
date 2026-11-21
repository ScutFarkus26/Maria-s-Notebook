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

// MARK: - Marking a child

/// Why `CDAttendanceStore.mark(student:status:reason:on:)` wrote nothing.
/// Each caller words it its own way: the grids in plain words
/// (`userMessage`), Siri as its own errors, Claude as a refusal that says why.
enum AttendanceMarkRefusal: Error, Equatable {
    /// Why a child isn't on the day's roll.
    enum OffRoll: Equatable {
        /// Her start date is after the day.
        case notStarted
        /// She left the class before the day (or has no id to mark).
        case departed
        /// A test student this device hides (`TestStudentsFilter`).
        case testStudent
    }

    /// This role may not write attendance (added as View only).
    case roleCannotWrite
    /// The day is locked; nobody's marks change until the guide unlocks it.
    case locked
    /// The child isn't on the day's roll, so a mark would put her there.
    case notOnRoll(OffRoll)
    /// Ahead of the day only an absence, or clearing a mark, is taken.
    case aheadOfDay
    /// The day has no school, and the caller hasn't confirmed the mark.
    case dayOff

    /// The plain sentence a grid shows.
    var userMessage: String {
        switch self {
        case .roleCannotWrite: "You can look at attendance here, but not change it."
        case .locked: "This day is locked, so its attendance can't be changed."
        case .notOnRoll(.notStarted): "That child hasn't started yet, so there's nothing to mark."
        case .notOnRoll: "That child isn't on this day's roll, so there's nothing to mark."
        case .aheadOfDay: "This day hasn't come yet. Only an absence can be marked ahead."
        case .dayOff: "There's no school this day, so attendance wasn't marked."
        }
    }
}

/// What `CDAttendanceStore.mark(student:status:reason:on:)` did.
struct AttendanceMarkOutcome {
    /// The child's record for the day: nil only when a child with no record
    /// was cleared, which writes nothing.
    let record: CDAttendanceRecord?
    /// Her mark before (unmarked when she had no record).
    let previous: AttendanceStatus
    /// Whether she held a mark before, read from the raw value as
    /// `AttendanceDeduplication.isMarked` reads it.
    let wasMarked: Bool
    /// The stored reason before.
    let previousReasonRaw: String
    /// The whole record before the mark, for an Undo; nil with no record.
    let before: AttendanceRecordSnapshot.Values?
    /// The record was made for this mark (the caller saves it).
    let created: Bool
    /// The status changed, or an automatic absence became the guide's.
    var statusChanged = false
    /// The absence's reason changed.
    var reasonChanged = false

    var changed: Bool { statusChanged || reasonChanged }

    /// Clearing a child who had no record: nothing to write.
    static var nothingToClear: AttendanceMarkOutcome {
        AttendanceMarkOutcome(
            record: nil, previous: .unmarked, wasMarked: false, previousReasonRaw: AbsenceReason.none.rawValue,
            before: nil, created: false
        )
    }
}

// MARK: - Date Normalization Helper

nonisolated extension Date {
    /// Returns the start of the day for this date using the provided calendar
    /// (the app's, in the classroom's time zone, unless another is given).
    func normalizedDay(using calendar: Calendar = AppCalendar.shared) -> Date {
        return calendar.startOfDay(for: self)
    }
}
