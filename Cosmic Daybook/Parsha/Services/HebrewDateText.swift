// HebrewDateText.swift
// The Hebrew date with English month names ("15 Cheshvan"), and the Schedules
// header line that carries it: "Monday, October 26 · 15 Cheshvan · Vayera".
// Builds for iOS 18: the Daybook Assistant shows the same header.

import Foundation

enum HebrewDateText {

    /// The months by Foundation's Hebrew month number, which is the same in
    /// every year: 6 is Adar I, which only a leap year has, and 7 is Adar, or
    /// Adar II in a leap year (`HebrewParshaService.isDisplacedShabbat`).
    private static let monthNames: [Int: String] = [
        1: "Tishrei", 2: "Cheshvan", 3: "Kislev", 4: "Tevet", 5: "Shevat", 6: "Adar I", 7: "Adar",
        8: "Nisan", 9: "Iyar", 10: "Sivan", 11: "Tammuz", 12: "Av", 13: "Elul"
    ]

    /// "15 Cheshvan", "14 Adar II", for the day `date` falls on (the daytime
    /// date: the Hebrew day that begins at the evening before). Nil when the
    /// calendar can't say.
    static func hebrewDate(for date: Date, hebrew: Calendar = HebrewParshaService.hebrew) -> String? {
        let parts = hebrew.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              var name = monthNames[month] else { return nil }
        if month == 7, isLeapYear(year) { name = "Adar II" }
        return "\(day) \(name)"
    }

    /// "Monday, October 26 · 15 Cheshvan · Vayera": the day (Today's
    /// subtitle), the Hebrew date, and the parsha read that week. A part the
    /// calendar can't give, or a week a festival takes the reading, is left out.
    static func headerLine(
        for date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = AppCalendar.shared
    ) -> String {
        var parts = [TodayHeaderText.subtitle(for: date, locale: locale, calendar: calendar)]
        if let hebrew = hebrewDate(for: date) { parts.append(hebrew) }
        if let key = HebrewParshaService.currentParshaKey(on: date) {
            parts.append(HebrewParshaService.displayName(forKey: key))
        }
        return parts.joined(separator: " · ")
    }

    /// Whether a Hebrew year has thirteen months: years 3, 6, 8, 11, 14, 17
    /// and 19 of the 19-year cycle.
    static func isLeapYear(_ year: Int) -> Bool {
        ((7 * year + 1) % 19 + 19) % 19 < 7
    }
}
