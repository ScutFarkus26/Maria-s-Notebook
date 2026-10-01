import CoreGraphics
import Foundation
import Testing
@testable import CosmicDaybook

/// The week strip's geometry: five days share the pane, the range label names
/// exactly the days the strip holds, and the insertion bar sits on the side of
/// a "Morning" / "Afternoon" label that matches the half the drop will take.
@Suite("Week plan layout")
@MainActor
struct WeekPlanLayoutTests {

    // MARK: - Column width

    @Test("Five days share a wide pane equally, padding and gaps taken out first")
    func fiveDaysFillTheWidth() {
        let width = WeekPlanSection.columnWidth(forStripWidth: 1_200, dayCount: 5)
        // 1,200 − 2 × 10 padding − 4 × 10 gaps = 1,140, a fifth of which is 228.
        #expect(width == 228)
        let used = width * 5 + WeekPlanSection.columnSpacing * 4 + WeekPlanSection.stripPadding * 2
        #expect(used <= 1_200)
    }

    @Test("An iPad in landscape, beside the sidebar, still fits all five days")
    func iPadLandscapeFitsFive() {
        // About 900 points of strip on an 11-inch iPad with the sidebar open.
        let width = WeekPlanSection.columnWidth(forStripWidth: 900, dayCount: 5)
        #expect(width > WeekPlanSection.minimumColumnWidth)
        let used = width * 5 + WeekPlanSection.columnSpacing * 4 + WeekPlanSection.stripPadding * 2
        #expect(used <= 900)
    }

    @Test("A pane too narrow for five falls back to the minimum and scrolls")
    func narrowPaneKeepsTheMinimum() {
        #expect(WeekPlanSection.columnWidth(forStripWidth: 390, dayCount: 5) == WeekPlanSection.minimumColumnWidth)
        // Not yet measured.
        #expect(WeekPlanSection.columnWidth(forStripWidth: 0, dayCount: 5) == WeekPlanSection.minimumColumnWidth)
    }

    // MARK: - Range label

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// Interval formatting puts thin and narrow no-break spaces around the
    /// dash; compare words, not whitespace.
    private func words(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{2009}\u{202F}")))
            .filter { !$0.isEmpty }
    }

    private let english = Locale(identifier: "en_US")

    @Test("A week inside one month names the month once")
    func sameMonth() {
        let label = WeekPlanSection.rangeLabel(
            first: day(2026, 9, 17), last: day(2026, 9, 23),
            calendar: calendar, locale: english, now: day(2026, 10, 1)
        )
        #expect(words(label) == ["Sep", "17", "–", "23"])
    }

    @Test("A week across two months names both, and not the current year")
    func acrossMonths() {
        let label = WeekPlanSection.rangeLabel(
            first: day(2026, 9, 28), last: day(2026, 10, 2),
            calendar: calendar, locale: english, now: day(2026, 10, 1)
        )
        #expect(words(label) == ["Sep", "28", "–", "Oct", "2"])
    }

    @Test("A week outside this year carries the year")
    func otherYear() {
        let label = WeekPlanSection.rangeLabel(
            first: day(2026, 12, 29), last: day(2027, 1, 4),
            calendar: calendar, locale: english, now: day(2026, 10, 1)
        )
        #expect(label.contains("2027"))
        #expect(label.contains("Dec"))
        #expect(label.contains("Jan"))
    }

    // MARK: - Insertion bar

    private func card(_ minY: CGFloat, _ half: DayPeriod) -> WeekDayColumn.PlacedCard {
        WeekDayColumn.PlacedCard(frame: CGRect(x: 0, y: minY, width: 200, height: 40), half: half)
    }

    /// Two morning cards, then the "Afternoon" label, then one afternoon card.
    private var twoHalves: [WeekDayColumn.PlacedCard] {
        [card(20, .morning), card(66, .morning), card(130, .afternoon)]
    }

    @Test("Inside a half, the bar sits just above the card the drop lands in front of")
    func barInsideAHalf() {
        #expect(WeekDayColumn.insertionBarY(at: 0, among: twoHalves) == 17)
        #expect(WeekDayColumn.insertionBarY(at: 1, among: twoHalves) == 63)
    }

    @Test("At the seam, the bar sits under the last morning card, above the Afternoon label")
    func barAtTheSeam() {
        // The drop takes the half of the card above it — the morning — so the
        // bar must not be drawn inside the afternoon band.
        #expect(WeekDayColumn.insertionBarY(at: 2, among: twoHalves) == 109)
        #expect(
            DayHalfPlanner.inheritedPeriod(insertingAt: 2, into: twoHalves.map(\.half)) == .morning
        )
    }

    @Test("Past the last card, and on an empty day")
    func barAtTheEnds() {
        #expect(WeekDayColumn.insertionBarY(at: 3, among: twoHalves) == 173)
        #expect(WeekDayColumn.insertionBarY(at: 0, among: []) == 16)
    }
}
