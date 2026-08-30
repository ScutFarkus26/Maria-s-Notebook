import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Covers the AM/PM half a scheduled presentation carries.
///
/// A scheduled presentation has no time, so the half is the only thing its
/// `scheduledFor` says about *when* — everything else in that date is ordering.
/// These are the rules that keep the two from being confused for each other:
/// which half a stored moment means, which half a drop inherits, and how a day
/// is numbered so a reorder can never walk one half into the other.
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

    private func placements(_ periods: [DayPeriod]) -> [DayHalfPlanner.Placement] {
        periods.map { DayHalfPlanner.Placement(id: UUID(), period: $0) }
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

    // MARK: - What a drop inherits

    @Test("A dropped lesson takes the half of the presentation above it")
    func dropInheritsFromAbove() {
        let day: [DayPeriod] = [.morning, .morning, .afternoon, .afternoon]

        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 1, into: day) == .morning)
        // The seam: dropped between the last morning and the first afternoon,
        // the card above is still a morning.
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 2, into: day) == .morning)
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 3, into: day) == .afternoon)
        // Past the last card, which is how the end of the day is reached.
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 4, into: day) == .afternoon)
    }

    @Test("A drop at the top of the day joins the run below it")
    func dropAtTheTopJoinsTheRunBelow() {
        // Nothing above to copy. Landing in the afternoon-only day the guide
        // aimed at beats opening a morning above it.
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 0, into: [.afternoon, .afternoon]) == .afternoon)
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 0, into: [.morning]) == .morning)
    }

    @Test("An empty day is a morning")
    func emptyDayIsMorning() {
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 0, into: []) == .morning)
        // An index past the end of an empty list is the same drop.
        #expect(DayHalfPlanner.inheritedPeriod(insertingAt: 3, into: []) == .morning)
    }

    // MARK: - Numbering

    @Test("Each half is numbered from its own base hour")
    func halvesAreNumberedSeparately() {
        let items = placements([.morning, .morning, .afternoon, .morning])
        let times = DayHalfPlanner.times(
            for: items,
            on: monday,
            using: AppCalendar.shared,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )

        #expect(times[items[0].id] == time(9, 0, 0, on: monday))
        #expect(times[items[1].id] == time(9, 0, 1, on: monday))
        #expect(times[items[2].id] == time(14, 0, 0, on: monday))
        // The third morning counts on from the second, not from the afternoon
        // that happens to sit between them in the list.
        #expect(times[items[3].id] == time(9, 0, 2, on: monday))
    }

    @Test("A morning can never be numbered into the afternoon")
    func aLongMorningStaysAMorning() {
        // A classroom's worth of lessons on one morning, spaced a second apart,
        // is still hours short of noon — which is what makes the hour safe to
        // read the half back out of.
        let items = placements(Array(repeating: DayPeriod.morning, count: 200))
        let times = DayHalfPlanner.times(
            for: items,
            on: monday,
            using: AppCalendar.shared,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        #expect(times.values.allSatisfy { DayPeriod(scheduledFor: $0) == .morning })
    }

    @Test("Numbering survives being read back as halves, in order")
    func numberingRoundTrips() {
        let items = placements([.morning, .afternoon, .morning, .afternoon])
        let times = DayHalfPlanner.times(
            for: items,
            on: monday,
            using: AppCalendar.shared,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )

        // Sorted by time — the order the calendar column draws — every morning
        // comes before every afternoon, whatever order they were numbered in.
        let sorted = items
            .compactMap { item in times[item.id].map { (item.period, $0) } }
            .sorted { $0.1 < $1.1 }
        #expect(sorted.map(\.0) == [.morning, .morning, .afternoon, .afternoon])
        #expect(sorted.allSatisfy { DayPeriod(scheduledFor: $0.1) == $0.0 })
    }

    // MARK: - Changing halves

    @Test("Sending a presentation to the afternoon puts it last in the afternoon")
    func moveToAfternoonLandsAtTheEnd() {
        let items = placements([.morning, .morning, .afternoon])
        let moved = DayHalfPlanner.movingToEndOfHalf(items[0].id, to: .afternoon, in: items)

        #expect(moved.map(\.id) == [items[1].id, items[2].id, items[0].id])
        #expect(moved.map(\.period) == [.morning, .afternoon, .afternoon])
    }

    @Test("Sending a presentation to the morning puts it last in the morning")
    func moveToMorningLandsBeforeTheAfternoon() {
        let items = placements([.morning, .afternoon, .afternoon])
        let moved = DayHalfPlanner.movingToEndOfHalf(items[2].id, to: .morning, in: items)

        #expect(moved.map(\.id) == [items[0].id, items[2].id, items[1].id])
        #expect(moved.map(\.period) == [.morning, .morning, .afternoon])
    }

    @Test("A half with no run yet still lands on the right side of the day")
    func moveIntoAnEmptyHalf() {
        let afternoonOnly = placements([.afternoon, .afternoon])
        let toMorning = DayHalfPlanner.movingToEndOfHalf(afternoonOnly[1].id, to: .morning, in: afternoonOnly)
        #expect(toMorning.map(\.id) == [afternoonOnly[1].id, afternoonOnly[0].id])

        let morningOnly = placements([.morning, .morning])
        let toAfternoon = DayHalfPlanner.movingToEndOfHalf(morningOnly[0].id, to: .afternoon, in: morningOnly)
        #expect(toAfternoon.map(\.id) == [morningOnly[1].id, morningOnly[0].id])
    }

    // MARK: - Through the store

    @Test("A day's halves and order survive being written and read back")
    func halvesSurviveRefetch() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let items = placements([.morning, .afternoon, .morning])
        for item in items {
            let assignment = CDLessonAssignment(context: context)
            assignment.id = item.id
            assignment.createdAt = monday
        }
        #expect(CoreDataTestHelpers.save(context))

        let times = DayHalfPlanner.times(
            for: items,
            on: monday,
            using: AppCalendar.shared,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        let request: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        for assignment in context.safeFetch(request) {
            if let id = assignment.id, let when = times[id] {
                assignment.schedule(for: when)
            }
        }
        #expect(CoreDataTestHelpers.save(context))

        let readBack = context.safeFetch(request)
            .sorted(by: LessonAssignmentOrdering.isOrderedBefore)
        // The afternoon lesson was numbered second and reads back last: the
        // column draws the day in halves without storing anything new.
        #expect(readBack.compactMap(\.id) == [items[0].id, items[2].id, items[1].id])
        #expect(
            readBack.compactMap { $0.scheduledFor.map { DayPeriod(scheduledFor: $0) } }
                == [.morning, .morning, .afternoon]
        )
        // The day mirror is still the day, whichever half the lesson is in.
        #expect(readBack.allSatisfy { $0.scheduledForDay == monday })
    }
}
