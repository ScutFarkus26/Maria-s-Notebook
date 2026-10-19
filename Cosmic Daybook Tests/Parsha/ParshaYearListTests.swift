import Foundation
import Testing
@testable import CosmicDaybook

/// The parsha screen's year list ends with Simchat Torah and V'Zot HaBerachah: no Shabbat carries
/// that reading, so without the row its lessons could not be reached from the screen.
@Suite("Parsha year list")
@MainActor
struct ParshaYearListTests {
    private let calendar = HebrewParshaService.gregorian

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    @Test("the list ends with V'Zot HaBerachah on the Simchat Torah that closes the cycle")
    func listEndsWithSimchatTorah() throws {
        // 5786's cycle ends on Simchat Torah 5787 (23 Tishri = 2026-10-04).
        let list = HebrewParshaService.parshaYearList(on: day(2026, 3, 1))
        let last = try #require(list.last)
        #expect(last.parshaKey == HebrewParshaService.vzotHaberachahKey)
        #expect(last.festivalName == nil)
        #expect(HebrewParshaService.isSimchatTorah(last.date))
        #expect(calendar.isDate(last.date, inSameDayAs: day(2026, 10, 4)))
        #expect(calendar.component(.weekday, from: last.date) != 7, "Simchat Torah is never a Saturday")
    }

    @Test("it follows the cycle's Shabbatot, in date order, and no Shabbat reads V'Zot HaBerachah")
    func listIsInOrder() {
        let list = HebrewParshaService.parshaYearList(on: day(2026, 3, 1))
        #expect(list.count > 40)
        #expect(list.map(\.date) == list.map(\.date).sorted())
        let shabbatot = list.dropLast()
        #expect(shabbatot.allSatisfy { $0.parshaKey != HebrewParshaService.vzotHaberachahKey })
        #expect(shabbatot.allSatisfy { calendar.component(.weekday, from: $0.date) == 7 })
        #expect(shabbatot.first?.parshaKey == "bereishit")
    }

    @Test("once the cycle's last Shabbat has passed, the list is the coming cycle's")
    func listMovesOnAfterTheLastShabbat() throws {
        // Shemini Atzeret fell on Shabbat 2026-10-03; on the 5th the old cycle is over.
        let before = try #require(HebrewParshaService.parshaYearList(on: day(2026, 10, 1)).last)
        let after = try #require(HebrewParshaService.parshaYearList(on: day(2026, 10, 5)).last)
        #expect(calendar.isDate(before.date, inSameDayAs: day(2026, 10, 4)))
        #expect(after.date > before.date)
        #expect(after.parshaKey == HebrewParshaService.vzotHaberachahKey)
        #expect(HebrewParshaService.isSimchatTorah(after.date))
    }

    @Test("an ordinary day is not Simchat Torah")
    func ordinaryDays() {
        #expect(!HebrewParshaService.isSimchatTorah(day(2026, 10, 3)))
        #expect(!HebrewParshaService.isSimchatTorah(day(2026, 3, 1)))
    }

    @Test("lessons tagged V'Zot HaBerachah are found by the key the list row carries")
    func rowKeyMatchesTheLessonQuery() {
        let key = HebrewParshaService.vzotHaberachahKey
        #expect(HebrewParshaService.lessonCount(forParshaKey: key, countsByTag: [key: 2]) == 2)
        #expect(HebrewParshaService.displayName(forKey: key) == "V'Zot HaBerachah")
    }
}
