import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Covers the AM/PM half a scheduled presentation carries.
///
/// A scheduled presentation has no time, so the half is the only thing its
/// `scheduledFor` says about *when* — everything else in that date is ordering.
/// These are the rules that keep the two from being confused for each other:
/// which half a stored moment means, and what switching halves keeps.
@Suite("Day halves")
@MainActor
struct DayHalfTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(AppCalendar.shared.date(from: components)!)
    }

    /// Monday 8 June 2026.
    private var monday: Date { day(2026, 6, 8) }

    private func time(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, on base: Date) -> Date {
        AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: second, of: base)!
    }

    // MARK: - Reading the half back out

    @Test("Noon is the boundary, not the base hours")
    func halfComesFromTheHour() {
        // An ordering slot in each half.
        #expect(DayPeriod(scheduledFor: time(9, 0, 3, on: monday)) == .morning)
        #expect(DayPeriod(scheduledFor: time(14, 0, 2, on: monday)) == .afternoon)

        // A time the guide set by hand still reads as the half it falls in.
        #expect(DayPeriod(scheduledFor: time(10, 30, on: monday)) == .morning)
        #expect(DayPeriod(scheduledFor: time(11, 59, 59, on: monday)) == .morning)
        #expect(DayPeriod(scheduledFor: time(12, 0, on: monday)) == .afternoon)

        // Rows written before halves existed sit at midnight, which is the
        // half the ordering base has always used.
        #expect(DayPeriod(scheduledFor: monday) == .morning)
    }

    @Test("Switching halves keeps the lesson's place in the day")
    func applyingAHalfKeepsTheOrderingOffset() {
        // The sixth lesson of the morning becomes the sixth of the afternoon,
        // rather than landing on top of whatever is at 2:00 sharp.
        #expect(
            DayPeriod.afternoon.applied(to: time(9, 0, 5, on: monday))
                == time(14, 0, 5, on: monday)
        )
        #expect(
            DayPeriod.morning.applied(to: time(14, 0, 5, on: monday))
                == time(9, 0, 5, on: monday)
        )

        // The hour is not carried across: a lesson set by hand for 10:30 in the
        // morning becomes an afternoon lesson, not a 10:30pm one.
        #expect(
            DayPeriod.afternoon.applied(to: time(10, 30, on: monday))
                == time(14, 30, on: monday)
        )

        // A legacy midnight row lands on the base hour of the half it is sent to.
        #expect(DayPeriod.afternoon.applied(to: monday) == time(14, 0, on: monday))
        #expect(DayPeriod.morning.applied(to: monday) == time(9, 0, on: monday))

        // And a half applied to a moment already in it changes nothing.
        let alreadyMorning = time(9, 0, 2, on: monday)
        #expect(DayPeriod.morning.applied(to: alreadyMorning) == alreadyMorning)
    }

    // MARK: - Ordering slot or a time somebody set

    @Test("A base hour on the minute is an ordering slot, whatever its seconds")
    func baseHoursReadAsHalves() {
        // Rank 0 of the morning: the encoding's own starting point.
        #expect(DayHalfPlanner.moment(of: time(9, 0, 0, on: monday)) == .half(.morning))
        // Rank 7 — the eighth lesson of the morning, not seven past nine.
        #expect(DayHalfPlanner.moment(of: time(9, 0, 7, on: monday)) == .half(.morning))
        #expect(DayHalfPlanner.moment(of: time(14, 0, 3, on: monday)) == .half(.afternoon))
    }

    @Test("Rows written before the halves existed sit at midnight and mean morning")
    func midnightIsLegacyMorning() {
        #expect(DayHalfPlanner.moment(of: monday) == .half(.morning))
        // The same answer `DayPeriod(scheduledFor:)` has always given them.
        #expect(DayPeriod(scheduledFor: monday) == .morning)
    }

    @Test("A time the guide set is reported as that time")
    func deliberateTimeSurvives() {
        let tenThirty = time(10, 30, 0, on: monday)
        #expect(DayHalfPlanner.moment(of: tenThirty) == .time(tenThirty))
        // Off the minute in a base hour is a set time too — the scheduler
        // writes second: 0, so only ordering puts seconds on a base hour.
        let quarterPastTwo = time(14, 15, 0, on: monday)
        #expect(DayHalfPlanner.moment(of: quarterPastTwo) == .time(quarterPastTwo))
    }
}
