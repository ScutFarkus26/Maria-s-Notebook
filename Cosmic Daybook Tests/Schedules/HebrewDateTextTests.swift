import Foundation
import Testing
@testable import CosmicDaybook

/// The Hebrew date with English month names, and the Schedules header line.
/// Every date is pinned against a published Hebrew calendar (Hebcal), each
/// taken at noon so the test holds in any time zone.
@Suite("Schedules: the Hebrew date")
@MainActor
struct HebrewDateTextTests {

    private typealias Support = TimetableTestSupport
    private let english = Locale(identifier: "en_US")

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Support.time(Support.day(year, month, day), 12)
    }

    @Test("Dates through the year, Adar I and II in a leap year, Adar in a plain one", arguments: [
        (2026, 10, 26, "15 Cheshvan"),
        (2026, 9, 12, "1 Tishrei"),
        (2025, 12, 15, "25 Kislev"),
        (2024, 2, 23, "14 Adar I"),
        (2024, 3, 24, "14 Adar II"),
        (2025, 3, 14, "14 Adar"),
        (2025, 4, 13, "15 Nisan")
    ])
    func hebrewDates(year: Int, month: Int, day: Int, expected: String) {
        #expect(HebrewDateText.hebrewDate(for: noon(year, month, day)) == expected)
    }

    @Test("The header: the day, the Hebrew date and the week's parsha")
    func headerLine() {
        #expect(
            HebrewDateText.headerLine(for: noon(2026, 10, 26), locale: english)
                == "Monday, October 26 · 15 Cheshvan · Vayera"
        )
        #expect(
            HebrewDateText.headerLine(for: noon(2026, 10, 30), locale: english)
                == "Friday, October 30 · 19 Cheshvan · Vayera"
        )
    }

    @Test("A week a festival takes the reading leaves the parsha out")
    func festivalWeek() {
        // Shabbat 3 October 2026 is Shemini Atzeret.
        #expect(
            HebrewDateText.headerLine(for: noon(2026, 9, 28), locale: english)
                == "Monday, September 28 · 17 Tishrei"
        )
    }

    @Test("Leap years: 3, 6, 8, 11, 14, 17 and 19 of the cycle")
    func leapYears() {
        #expect([5782, 5784, 5787].allSatisfy(HebrewDateText.isLeapYear))
        #expect(![5783, 5785, 5786, 5788].contains(where: HebrewDateText.isLeapYear))
    }
}
