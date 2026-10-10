import Foundation
import Testing
@testable import CosmicDaybook

/// The Scheduled strip's window: it loads more days only when a scroll comes
/// to rest, keeps the day that was leading when days go in front of it, and
/// adds them once per scroll however the scroll view reports the move.
@Suite("Week plan day window")
@MainActor
struct WeekPlanDayWindowTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)) ?? Date()
    }

    private func isWeekday(_ date: Date) -> Bool {
        !calendar.isDateInWeekend(date)
    }

    /// `count` weekdays starting on or after `start`.
    private func weekdays(from start: Date, count: Int) -> [Date] {
        var result: [Date] = []
        var cursor = start
        while result.count < count {
            if isWeekday(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }

    /// The `count` weekdays before `first`.
    private func weekdays(before first: Date, count: Int) -> [Date] {
        var result: [Date] = []
        var cursor = first
        while result.count < count {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            if isWeekday(cursor) { result.insert(cursor, at: 0) }
        }
        return result
    }

    private let margins = WeekPlanDayWindow.Margins(front: 5, back: 10)

    private func grow(_ days: [Date], leading: Date) -> WeekPlanDayWindow.Growth? {
        WeekPlanDayWindow.grown(
            days: days,
            leadingDay: leading,
            margins: margins,
            earlierDays: { weekdays(before: $0, count: 20) },
            laterDays: { last in
                weekdays(from: calendar.date(byAdding: .day, value: 1, to: last) ?? last, count: 20)
            }
        )
    }

    @Test("Growth at the front keeps the leading day and adds once for one scroll")
    func frontGrowthKeepsTheLeadingDayOnce() throws {
        let days = weekdays(from: monday, count: 45)
        let leading = days[2]
        var settle = WeekPlanDayWindow.Settle()

        // The guide scrolls toward the front: nothing loads mid-scroll.
        let startedAtRest = settle.scrollPhaseChanged(isScrolling: true)
        #expect(startedAtRest == false)
        #expect(settle.canSettle == false)

        // It comes to rest: the one moment the ends are checked.
        let cameToRest = settle.scrollPhaseChanged(isScrolling: false)
        #expect(cameToRest)
        #expect(settle.canSettle)
        let growth = try #require(grow(days, leading: leading))
        #expect(growth.addedInFront == 20)
        #expect(growth.addedAtEnd == 0)
        #expect(growth.leadingDay == leading)
        #expect(growth.days.count == 65)
        #expect(growth.days.firstIndex(of: leading) == 22)
        // The days from the leading one on are the ones that were there.
        #expect(Array(growth.days[22...]) == Array(days[2...]))
        #expect(growth.days == growth.days.sorted())

        holdThroughLayout(&settle, growth: growth, leading: leading)
    }

    /// The scroll view kept its offset, so it reports an earlier day while the
    /// strip puts the leading one back: that is not a scroll, however many
    /// times it comes, and however late. Only the held day ends the hold, and
    /// settling on it adds nothing more.
    private func holdThroughLayout(
        _ settle: inout WeekPlanDayWindow.Settle,
        growth: WeekPlanDayWindow.Growth,
        leading: Date
    ) {
        settle.pin(leading)
        #expect(settle.canSettle == false)
        let shifted = growth.days[2]
        let shiftedIndex: Int = growth.days.firstIndex(of: shifted) ?? Int.max
        #expect(shiftedIndex < margins.front)
        let firstShift = settle.leadingDayReported(shifted)
        let secondShift = settle.leadingDayReported(growth.days[3])
        #expect(firstShift == false)
        #expect(secondShift == false)
        #expect(settle.pinnedDay == leading)
        // Still at rest: no scroll has begun, so none can come to rest.
        let restedAgain = settle.scrollPhaseChanged(isScrolling: false)
        #expect(restedAgain == false)
        #expect(settle.pinnedDay == leading)

        // The report naming the held day lets go of it, and is not itself a
        // reason to grow.
        let putBack = settle.leadingDayReported(leading)
        #expect(putBack == false)
        #expect(settle.pinnedDay == nil)
        #expect(settle.canSettle)

        // Settling again on the day put back adds nothing more.
        #expect(grow(growth.days, leading: leading) == nil)

        // After that, a move at rest is the guide's again.
        let guideMove = settle.leadingDayReported(growth.days[30])
        #expect(guideMove)
    }

    @Test("A scroll that comes to rest lets go of a held day and checks the ends")
    func restReleasesThePin() {
        var settle = WeekPlanDayWindow.Settle()
        settle.pin(monday)
        _ = settle.scrollPhaseChanged(isScrolling: true)
        // A report mid-scroll waits for the rest, held day or not.
        let midScroll = settle.leadingDayReported(monday)
        #expect(midScroll == false)
        let cameToRest = settle.scrollPhaseChanged(isScrolling: false)
        #expect(cameToRest)
        #expect(settle.pinnedDay == nil)
        #expect(settle.canSettle)
    }

    @Test("The safety cap lets go of the held day, and only that day")
    func capReleasesOnlyItsOwnPin() {
        var settle = WeekPlanDayWindow.Settle()
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        settle.pin(tuesday)
        // An older hold's cap firing late leaves a newer hold alone.
        settle.releasePin(holding: monday)
        #expect(settle.pinnedDay == tuesday)
        settle.releasePin(holding: tuesday)
        #expect(settle.pinnedDay == nil)
        #expect(settle.canSettle)
    }

    @Test("Reports while the guide scrolls wait for the scroll to come to rest")
    func reportsWhileScrollingWait() {
        var settle = WeekPlanDayWindow.Settle()
        let atRest = settle.leadingDayReported(monday)
        #expect(atRest)
        _ = settle.scrollPhaseChanged(isScrolling: true)
        let scrolling = settle.leadingDayReported(monday)
        #expect(scrolling == false)
    }

    @Test("Near the far end, later days load and nothing goes in front")
    func backGrowth() throws {
        let days = weekdays(from: monday, count: 45)
        let leading = days[40]
        let growth = try #require(grow(days, leading: leading))
        #expect(growth.addedInFront == 0)
        #expect(growth.addedAtEnd == 20)
        #expect(Array(growth.days.prefix(45)) == days)
        #expect(growth.days.firstIndex(of: leading) == 40)
        #expect(growth.days == growth.days.sorted())
    }

    @Test("In the middle of the window nothing loads")
    func middleLoadsNothing() {
        let days = weekdays(from: monday, count: 45)
        #expect(grow(days, leading: days[5]) == nil)
        #expect(grow(days, leading: days[35]) == nil)
    }

    @Test("With no school days left before the window, the front stays as it is")
    func noEarlierDays() {
        let days = weekdays(from: monday, count: 45)
        let growth = WeekPlanDayWindow.grown(
            days: days, leadingDay: days[0], margins: margins,
            earlierDays: { _ in [] }, laterDays: { _ in [] }
        )
        #expect(growth == nil)
    }

    @Test("Days the window already holds are not added again")
    func overlapIsDropped() throws {
        let days = weekdays(from: monday, count: 45)
        let growth = try #require(WeekPlanDayWindow.grown(
            days: days, leadingDay: days[1], margins: margins,
            // A source that runs up to and past the first day.
            earlierDays: { first in weekdays(before: first, count: 3) + [first, days[1]] },
            laterDays: { _ in [] }
        ))
        #expect(growth.addedInFront == 3)
        #expect(Set(growth.days).count == growth.days.count)
        #expect(growth.days.firstIndex(of: days[1]) == 4)
    }

    @Test("A day that is not in the window loads nothing")
    func unknownLeadingDay() {
        let days = weekdays(from: monday, count: 45)
        let saturday = calendar.date(byAdding: .day, value: 5, to: monday) ?? monday
        #expect(grow(days, leading: saturday) == nil)
    }
}
