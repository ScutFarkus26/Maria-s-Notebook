// HebrewBirthday.swift
// A child's Hebrew birthday, worked out from the date of birth and whether
// they were born after sunset (a Hebrew date begins at sunset, so an evening
// birth takes the next day's date). Computed wherever it's shown, never
// stored, so correcting either field updates it everywhere.
//
// Notebook only: the Daybook Assistant compiles none of this
// (docs/Plans/Plan - Hebrew birthdays.md › Decisions).
//
// Foundation turns the Hebrew day at midnight, not sunset, and in whatever
// zone its calendar has. So the stored birthday's year, month and day are
// read with the app's Gregorian calendar (the day the child's page shows),
// and that day is converted at noon in one fixed zone (UTC), where midnight
// is twelve hours away on either side. A Hebrew date found in a later year
// goes back to a local day through the same Gregorian calendar.

import Foundation

nonisolated struct HebrewBirthday: Sendable, Hashable {

    /// A Hebrew date in Foundation's numbering, which is the same in every
    /// year: 1 Tishri … 5 Shevat, 6 Adar I (leap years only), 7 Adar (Adar II
    /// in a leap year), 8 Nisan … 13 Elul.
    struct Components: Sendable, Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    /// The Hebrew date the child was born on.
    let hebrewComponents: Components

    /// `calendar` reads the stored birthday and is the Gregorian calendar the
    /// app shows it with (`AppCalendar.shared`). Nil only when Foundation
    /// can't convert the date.
    init?(birthday: Date, bornAfterSunset: Bool, calendar: Calendar = AppCalendar.shared) {
        guard let noon = Self.utcNoon(of: birthday, calendar: calendar, addingDays: bornAfterSunset ? 1 : 0),
              let components = Self.hebrewComponents(atUTCNoon: noon) else { return nil }
        hebrewComponents = components
    }

    // MARK: - Writing it

    /// "14 Adar II 5784", "3 Heshvan 5787".
    var english: String { Self.englishStyle.format(noon) }

    /// "י״ד באדר ב׳ ה׳תשפ״ד".
    var hebrew: String { Self.hebrewStyle.format(noon) }

    /// "14 Adar II 5784 · י״ד באדר ב׳ ה׳תשפ״ד".
    var display: String { "\(english) · \(hebrew)" }

    /// "14 Adar II": the Hebrew day and month of a local day, such as the one
    /// `nextOccurrence` gives (which names that year's month: a child born in
    /// Adar II has "14 Adar" in a regular year).
    static func englishDayAndMonth(on day: Date, calendar: Calendar = AppCalendar.shared) -> String? {
        utcNoon(of: day, calendar: calendar).map(dayAndMonthStyle.format)
    }

    // MARK: - Later years

    /// The local day (start of day in `calendar`) of the next Hebrew birthday
    /// on or after `start`'s day, so a birthday today counts.
    ///
    /// In a later year:
    /// - Adar of a regular year and Adar II fall in Adar II of a leap year and
    ///   Adar of a regular one (both are month 7).
    /// - Adar I falls in Adar I of a leap year and Adar of a regular one.
    /// - A 30th the month lacks that year (Heshvan and Kislev have 29 days in
    ///   some years; Adar of a regular year always does) falls on the 1st of
    ///   the next month: 30 Adar I in a regular year is 1 Nisan.
    func nextOccurrence(onOrAfter start: Date, calendar: Calendar = AppCalendar.shared) -> Date {
        let startOfDay = calendar.startOfDay(for: start)
        guard let noon = Self.utcNoon(of: start, calendar: calendar),
              let year = Self.hebrewComponents(atUTCNoon: noon)?.year else { return startOfDay }
        for candidate in [year, year + 1] {
            if let day = occurrence(inHebrewYear: candidate, calendar: calendar), day >= startOfDay {
                return day
            }
        }
        return startOfDay
    }

    /// The local day of the birthday in one Hebrew year.
    private func occurrence(inHebrewYear year: Int, calendar: Calendar) -> Date? {
        let month = hebrewComponents.month == 6 && !Self.isLeapYear(year) ? 7 : hebrewComponents.month
        // The 1st of the month plus the days after it, so a 30th the month
        // lacks rolls over to the next month's 1st.
        guard let first = Self.hebrewUTC.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let noon = Self.hebrewUTC.date(byAdding: .day, value: hebrewComponents.day - 1, to: first) else {
            return nil
        }
        let parts = Self.gregorianUTC.dateComponents([.year, .month, .day], from: noon)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }

    // MARK: - Converting

    private static let hebrewUTC: Calendar = {
        var cal = Calendar(identifier: .hebrew)
        cal.timeZone = .gmt
        return cal
    }()

    private static let gregorianUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return cal
    }()

    /// Noon UTC on the Gregorian day `date` falls on in `calendar`, moved
    /// `addingDays` later.
    private static func utcNoon(of date: Date, calendar: Calendar, addingDays: Int = 0) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let noon = gregorianUTC.date(from: DateComponents(
            year: parts.year, month: parts.month, day: parts.day, hour: 12
        )) else { return nil }
        return gregorianUTC.date(byAdding: .day, value: addingDays, to: noon)
    }

    /// Whether a Hebrew year has Adar I: building its month 6 gives month 6
    /// back only then (a regular year gives Adar, month 7). The calendar's
    /// `isLeapMonth` and month range can't say.
    private static func isLeapYear(_ year: Int) -> Bool {
        let adarI = DateComponents(year: year, month: 6, day: 1, hour: 12)
        guard let date = hebrewUTC.date(from: adarI) else { return false }
        return hebrewUTC.component(.month, from: date) == 6
    }

    private static func hebrewComponents(atUTCNoon noon: Date) -> Components? {
        let parts = hebrewUTC.dateComponents([.year, .month, .day], from: noon)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return Components(year: year, month: month, day: day)
    }

    /// Noon UTC of the birth's Hebrew date, for the formatters.
    private var noon: Date {
        Self.hebrewUTC.date(from: DateComponents(
            year: hebrewComponents.year, month: hebrewComponents.month, day: hebrewComponents.day, hour: 12
        )) ?? .distantPast
    }

    // MARK: - Formats
    // `.month(.wide)` names Adar, Adar I and Adar II by the year; the
    // calendar is set on the style because a locale's @calendar is ignored.

    private static let englishStyle = Date.VerbatimFormatStyle(
        format: "\(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
        locale: Locale(identifier: "en_US"), timeZone: .gmt, calendar: hebrewUTC
    )

    private static let dayAndMonthStyle = Date.VerbatimFormatStyle(
        format: "\(day: .defaultDigits) \(month: .wide)",
        locale: Locale(identifier: "en_US"), timeZone: .gmt, calendar: hebrewUTC
    )

    /// Hebrew script with Hebrew numerals.
    private static let hebrewStyle = Date.FormatStyle(
        date: .long, time: .omitted,
        locale: Locale(identifier: "he_IL@numbers=hebr"), calendar: hebrewUTC, timeZone: .gmt
    )
}
