import Foundation
import Testing
@testable import CosmicDaybook

// A child's Hebrew birthday from the date of birth and the "Born after
// sunset" switch (docs/Plans/Plan - Hebrew birthdays.md). Every expected
// answer is a literal looked up on Hebcal's converter on 2026-10-25
// (https://www.hebcal.com/converter?cfg=json&gy=…&gm=…&gd=…&g2h=1, and
// `h2g=1` the other way), never worked out with Foundation here, which would
// only check the code against itself.
//
// Most cases build the birthday at local midnight in the run's own zone, the
// way the date picker stores it; the suite runs once plainly and once under
// TEST_RUNNER_TZ=GMT-1000. The zone cases use fixed instants and name their
// zones, so they mean the same thing in any run.
@Suite("Hebrew birthday")
struct HebrewBirthdayTests {

    /// Gregorian in the run's zone, as `AppCalendar.shared` is.
    private let local: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    private func calendar(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, in cal: Calendar? = nil) -> Date {
        (cal ?? local).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func instant(_ iso: String) throws -> Date {
        try Date(iso, strategy: .iso8601)
    }

    private func hebrew(_ year: Int, _ month: Int, _ day: Int, afterSunset: Bool = false) -> HebrewBirthday? {
        HebrewBirthday(birthday: self.day(year, month, day), bornAfterSunset: afterSunset, calendar: local)
    }

    private func next(_ birthday: HebrewBirthday?, onOrAfter start: Date) -> Date? {
        birthday?.nextOccurrence(onOrAfter: start, calendar: local)
    }

    // MARK: - The date

    // Hebcal: 2024-03-24 = 14 Adar II 5784 (Purim), 2025-03-14 = 14 Adar 5785
    // (Purim), 2015-03-04 = 13 Adar 5775, 2024-02-23 = 14 Adar I 5784,
    // 2024-03-10 = 30 Adar I 5784, 2024-12-01 = 30 Cheshvan 5785,
    // 2022-12-24 = 30 Kislev 5783.
    nonisolated struct DateCase: Sendable, CustomTestStringConvertible {
        let born: [Int]
        let english: String
        let hebrew: HebrewBirthday.Components
        var testDescription: String { english }
    }

    nonisolated static let dateCases: [DateCase] = [
        DateCase(born: [2024, 3, 24], english: "14 Adar II 5784", hebrew: .init(year: 5784, month: 7, day: 14)),
        DateCase(born: [2025, 3, 14], english: "14 Adar 5785", hebrew: .init(year: 5785, month: 7, day: 14)),
        DateCase(born: [2015, 3, 4], english: "13 Adar 5775", hebrew: .init(year: 5775, month: 7, day: 13)),
        DateCase(born: [2024, 2, 23], english: "14 Adar I 5784", hebrew: .init(year: 5784, month: 6, day: 14)),
        DateCase(born: [2024, 3, 10], english: "30 Adar I 5784", hebrew: .init(year: 5784, month: 6, day: 30)),
        DateCase(born: [2024, 12, 1], english: "30 Heshvan 5785", hebrew: .init(year: 5785, month: 2, day: 30)),
        DateCase(born: [2022, 12, 24], english: "30 Kislev 5783", hebrew: .init(year: 5783, month: 3, day: 30))
    ]

    // Hebcal: 2024-03-24 = 14 Adar II 5784 (Purim), 2025-03-14 = 14 Adar 5785
    // (Purim), 2015-03-04 = 13 Adar 5775, 2024-02-23 = 14 Adar I 5784,
    // 2024-03-10 = 30 Adar I 5784, 2024-12-01 = 30 Cheshvan 5785,
    // 2022-12-24 = 30 Kislev 5783.
    @Test("Dates in English, with Adar, Adar I and Adar II named by the year", arguments: dateCases)
    func englishDates(_ dateCase: DateCase) throws {
        let birthday = try #require(hebrew(dateCase.born[0], dateCase.born[1], dateCase.born[2]))
        #expect(birthday.english == dateCase.english)
        #expect(birthday.hebrewComponents == dateCase.hebrew)
    }

    // Hebcal gives the letters "י״ד בַּאֲדָר ב׳ תשפ״ד" and "י״ג בַּאֲדָר תשע״ה";
    // Foundation writes them without vowel points and with the thousands (ה׳).
    @Test("Dates in Hebrew script, and both together")
    func hebrewScript() throws {
        let purim5784 = try #require(hebrew(2024, 3, 24))
        #expect(purim5784.hebrew == "י״ד באדר ב׳ ה׳תשפ״ד")
        #expect(purim5784.display == "14 Adar II 5784 · י״ד באדר ב׳ ה׳תשפ״ד")
        #expect(try #require(hebrew(2015, 3, 4)).hebrew == "י״ג באדר ה׳תשע״ה")
    }

    @Test("The day and month alone, for a day that is already a Hebrew birthday")
    func dayAndMonth() {
        // Hebcal: 2027-03-23 = 14 Adar II 5787, 2026-03-03 = 14 Adar 5786.
        #expect(HebrewBirthday.englishDayAndMonth(on: day(2027, 3, 23), calendar: local) == "14 Adar II")
        #expect(HebrewBirthday.englishDayAndMonth(on: day(2026, 3, 3), calendar: local) == "14 Adar")
    }

    // MARK: - Born after sunset

    @Test("Born after sunset takes the next day's Hebrew date, across a month's end")
    func afterSunsetAcrossMonthEnd() throws {
        // Hebcal: 2024-03-09 = 29 Adar I, 2024-03-10 = 30 Adar I, 2024-03-11 = 1 Adar II 5784.
        #expect(try #require(hebrew(2024, 3, 9, afterSunset: true)).english == "30 Adar I 5784")
        #expect(try #require(hebrew(2024, 3, 10, afterSunset: true)).english == "1 Adar II 5784")
        // Hebcal: 2023-11-13 = 29 Cheshvan, 2023-11-14 = 1 Kislev 5784.
        #expect(try #require(hebrew(2023, 11, 13)).english == "29 Heshvan 5784")
        #expect(try #require(hebrew(2023, 11, 13, afterSunset: true)).english == "1 Kislev 5784")
    }

    @Test("Born after sunset on the last day of a Gregorian month or year")
    func afterSunsetAcrossGregorianEnds() throws {
        // Hebcal: 2024-03-01 = 21 Adar I 5784; 2025-01-01 = 1 Tevet 5785.
        #expect(try #require(hebrew(2024, 2, 29, afterSunset: true)).english == "21 Adar I 5784")
        #expect(try #require(hebrew(2024, 12, 31)).english == "30 Kislev 5785")
        #expect(try #require(hebrew(2024, 12, 31, afterSunset: true)).english == "1 Tevet 5785")
    }

    // MARK: - Later years

    @Test("Born in Adar of a regular year: Adar in a regular year, Adar II in a leap year")
    func adarInLaterYears() {
        let birthday = hebrew(2025, 3, 14)
        // Hebcal: 14 Adar 5786 = 2026-03-03; 14 Adar II 5787 = 2027-03-23.
        #expect(next(birthday, onOrAfter: day(2025, 9, 30)) == day(2026, 3, 3))
        #expect(next(birthday, onOrAfter: day(2026, 9, 15)) == day(2027, 3, 23))
    }

    @Test("Born in Adar I: Adar in a regular year, Adar I in a leap year")
    func adarIInLaterYears() {
        let birthday = hebrew(2024, 2, 23)
        // Hebcal: 14 Adar 5785 = 2025-03-14; 14 Adar I 5787 = 2027-02-21.
        #expect(next(birthday, onOrAfter: day(2024, 10, 10)) == day(2025, 3, 14))
        #expect(next(birthday, onOrAfter: day(2026, 10, 1)) == day(2027, 2, 21))
    }

    @Test("Born in Adar II: Adar in a regular year, Adar II in a leap year")
    func adarIIInLaterYears() {
        let birthday = hebrew(2024, 3, 24)
        // Hebcal: 14 Adar 5785 = 2025-03-14; 14 Adar II 5787 = 2027-03-23.
        #expect(next(birthday, onOrAfter: day(2024, 10, 10)) == day(2025, 3, 14))
        #expect(next(birthday, onOrAfter: day(2026, 10, 1)) == day(2027, 3, 23))
    }

    @Test("Born on 30 Heshvan: 1 Kislev in a year whose Heshvan has 29 days")
    func thirtiethOfHeshvan() {
        // Hebcal: 2024-12-01 = 30 Cheshvan 5785. In 5786, 29 Cheshvan =
        // 2025-11-20 and 1 Kislev = 2025-11-21, so that Heshvan has 29 days.
        #expect(next(hebrew(2024, 12, 1), onOrAfter: day(2025, 10, 1)) == day(2025, 11, 21))
    }

    @Test("Born on 30 Kislev: 1 Tevet in a year whose Kislev has 29 days, the 30th when it has 30")
    func thirtiethOfKislev() {
        let birthday = hebrew(2022, 12, 24)
        // Hebcal: 2022-12-24 = 30 Kislev 5783. In 5784, 29 Kislev = 2023-12-12
        // and 1 Tevet = 2023-12-13. 30 Kislev 5785 = 2024-12-31.
        #expect(next(birthday, onOrAfter: day(2023, 10, 1)) == day(2023, 12, 13))
        #expect(next(birthday, onOrAfter: day(2024, 10, 10)) == day(2024, 12, 31))
    }

    @Test("Born on 30 Adar I: 1 Nisan in a regular year, 30 Adar I in a leap year")
    func thirtiethOfAdarI() {
        let birthday = hebrew(2024, 3, 10)
        // Hebcal: 29 Adar 5785 = 2025-03-29, 1 Nisan 5785 = 2025-03-30;
        // 30 Adar I 5787 = 2027-03-09.
        #expect(next(birthday, onOrAfter: day(2024, 10, 10)) == day(2025, 3, 30))
        #expect(next(birthday, onOrAfter: day(2026, 10, 1)) == day(2027, 3, 9))
    }

    // MARK: - Next occurrence edges

    @Test("A Hebrew birthday today counts, from any time of the day")
    func birthdayToday() {
        let birthday = hebrew(2025, 3, 14)
        let afternoon = local.date(byAdding: .hour, value: 15, to: day(2026, 3, 3))!
        #expect(next(birthday, onOrAfter: day(2026, 3, 3)) == day(2026, 3, 3))
        #expect(next(birthday, onOrAfter: afternoon) == day(2026, 3, 3))
        // The day after, it's next year's: 14 Adar II 5787.
        #expect(next(birthday, onOrAfter: day(2026, 3, 4)) == day(2027, 3, 23))
    }

    @Test("A Hebrew birthday on the last day of a seven-day window falls inside it")
    func lastDayOfWeekWindow() throws {
        let start = day(2026, 2, 25)
        let found = try #require(next(hebrew(2025, 3, 14), onOrAfter: start))
        #expect(found == day(2026, 3, 3))
        #expect(found == local.date(byAdding: .day, value: 6, to: start))
        #expect(found < local.date(byAdding: .day, value: 7, to: start)!)
    }

    @Test("The default calendar is the app's")
    func defaultsToAppCalendar() throws {
        let born = AppCalendar.shared.date(from: DateComponents(year: 2024, month: 3, day: 24))!
        let birthday = try #require(HebrewBirthday(birthday: born, bornAfterSunset: false))
        #expect(birthday.english == "14 Adar II 5784")
        let start = AppCalendar.shared.date(from: DateComponents(year: 2024, month: 10, day: 10))!
        #expect(birthday.nextOccurrence(onOrAfter: start)
            == AppCalendar.shared.date(from: DateComponents(year: 2025, month: 3, day: 14)))
    }

    // MARK: - Time zones

    @Test("A birthday stored at UTC midnight follows the Gregorian day each zone shows")
    func utcMidnightBirthday() throws {
        // As an old backup or the MCP may store 4 March 2015. New York and
        // Honolulu show it as 3 March, which Hebcal gives as 12 Adar 5775;
        // UTC and Tokyo show 4 March, 13 Adar 5775.
        let born = try instant("2015-03-04T00:00:00Z")
        let expected = [
            "UTC": "13 Adar 5775",
            "Asia/Tokyo": "13 Adar 5775",
            "America/New_York": "12 Adar 5775",
            "Pacific/Honolulu": "12 Adar 5775"
        ]
        for (zone, english) in expected {
            let birthday = HebrewBirthday(birthday: born, bornAfterSunset: false, calendar: calendar(zone))
            #expect(birthday?.english == english, "\(zone)")
        }
    }

    @Test("A birthday picked at midnight in Tokyo reads as that day there")
    func tokyoMidnightBirthday() throws {
        // Midnight of 4 March 2015 in Tokyo is still 3 March in UTC and
        // the Americas. Hebcal: 2015-03-04 = 13 Adar 5775, the 5th = 14 Adar.
        let born = try instant("2015-03-03T15:00:00Z")
        let tokyo = calendar("Asia/Tokyo")
        #expect(HebrewBirthday(birthday: born, bornAfterSunset: false, calendar: tokyo)?.english == "13 Adar 5775")
        #expect(HebrewBirthday(birthday: born, bornAfterSunset: true, calendar: tokyo)?.english == "14 Adar 5775")
    }

    @Test("The next occurrence is the local day in the calendar's own zone", arguments: [
        "Pacific/Honolulu", "America/New_York", "UTC", "Asia/Tokyo"
    ])
    func nextOccurrenceInZone(zone: String) throws {
        let cal = calendar(zone)
        let birthday = try #require(
            HebrewBirthday(birthday: day(2025, 3, 14, in: cal), bornAfterSunset: false, calendar: cal)
        )
        // Hebcal: 14 Adar 5786 = 2026-03-03.
        let found = birthday.nextOccurrence(onOrAfter: day(2026, 1, 1, in: cal), calendar: cal)
        #expect(found == day(2026, 3, 3, in: cal))
        // Late in the evening of the day itself, it still counts.
        let lateEvening = try #require(cal.date(byAdding: .hour, value: 23, to: day(2026, 3, 3, in: cal)))
        #expect(birthday.nextOccurrence(onOrAfter: lateEvening, calendar: cal) == day(2026, 3, 3, in: cal))
    }
}
