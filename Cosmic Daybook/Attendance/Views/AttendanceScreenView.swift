// AttendanceScreenView.swift
// The Attendance screen's two views: the roll for one day, and the list of
// every mark over a date range, with its status filter and totals. The list
// was the Attendance log under Logs, a screen that only repeated this one
// (plan "Simplify the app", Phase 2). On the Mac and iPad the two sit side by
// side in the toolbar; the iPhone opens the list from its toolbar.

import Foundation

enum AttendanceScreenView: String, CaseIterable, Identifiable, Sendable {
    /// One day's roll, beside Insights and the month.
    case roll
    /// Every mark over a date range (`AttendanceLogView`).
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .roll: "Roll"
        case .list: "List"
        }
    }

    /// Resolves a saved view, falling back to the roll.
    static func resolved(rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .roll
    }

    /// Saves the roll as the screen's view. A route that has to land on the
    /// roll (the 9:00 reminder's email offer is made there; Siri's "open
    /// attendance") sets this first: the open screen follows the saved view,
    /// and a screen opened later starts on it.
    static func showRoll(defaults: UserDefaults = .standard) {
        defaults.set(Self.roll.rawValue, forKey: UserDefaultsKeys.attendanceScreenView)
    }
}
