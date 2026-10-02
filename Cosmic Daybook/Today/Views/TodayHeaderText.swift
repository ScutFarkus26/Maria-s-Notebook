// TodayHeaderText.swift
// The words Today's header says: the Mac window subtitle's date and the
// attendance band's one line. Pure, so the tests pin them.

import Foundation

enum TodayHeaderText {

    /// The Mac window subtitle under "Today": "Wednesday, September 23".
    static func subtitle(
        for date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = AppCalendar.shared
    ) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide)
                .month(.wide)
                .day()
        )
    }
}

/// What the attendance band says: "19 here · 2 late · 3 absent", with the
/// absent (and left-early) children named. Names arrive already in
/// short-name format and in display order.
struct TodayAttendanceBandSummary: Equatable {
    var hereCount: Int
    var lateCount: Int
    var absentCount: Int
    var leftEarlyCount: Int
    var lateNames: [String] = []
    var absentNames: [String] = []
    var leftEarlyNames: [String] = []

    var hereText: String { "\(hereCount) here" }
    var lateText: String? { lateCount > 0 ? "\(lateCount) late" : nil }
    var absentText: String? { absentCount > 0 ? "\(absentCount) absent" : nil }
    var leftEarlyText: String? { leftEarlyCount > 0 ? "\(leftEarlyCount) left early" : nil }

    /// The late count's tooltip: who came in late, or just the count until
    /// the names have loaded.
    var lateHelp: String {
        guard let lateText else { return "" }
        return lateNames.isEmpty ? lateText : "Late: " + lateNames.joined(separator: ", ")
    }

    /// One VoiceOver line for the whole band:
    /// "19 here, 2 late, 3 absent: Chaviva F, Leora F, Zahava W".
    /// A group that names children is set off from the next by a semicolon,
    /// so the names never run into the following count.
    var accessibilityLabel: String {
        var groups: [(text: String, names: [String])] = [(hereText, [])]
        if let lateText { groups.append((lateText, lateNames)) }
        if let absentText { groups.append((absentText, absentNames)) }
        if let leftEarlyText { groups.append((leftEarlyText, leftEarlyNames)) }

        var label = ""
        var previousHadNames = false
        for group in groups {
            if !label.isEmpty { label += previousHadNames ? "; " : ", " }
            label += group.text
            if !group.names.isEmpty {
                label += ": " + group.names.joined(separator: ", ")
            }
            previousHadNames = !group.names.isEmpty
        }
        return label
    }
}
