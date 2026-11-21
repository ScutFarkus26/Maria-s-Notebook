import Foundation
import Testing
@testable import CosmicDaybook

/// Lessons less than `LessonLength.assumedMinutes` apart clash on the planner,
/// as they do in free times (plan "Domain logic fixes", decision 5): the day
/// badge and the time chips flag 9:00 and 9:15, never 9:00 and 9:30.
@Suite("Planning: lessons that overlap")
@MainActor
struct LessonOverlapClashTests {

    private let calendar = AppCalendar.shared
    private let day = TimetableTestSupport.monday

    /// A time the guide set: 9:00 carries the marker second, so it isn't read as a slot.
    private func at(_ hour: Int, _ minute: Int) -> Date {
        DayHalfPlanner.settingTime(hour: hour, minute: minute, on: day)
    }

    @Test("A 9:00 and a 9:15 lesson clash; a 9:30 one after 9:00 doesn't")
    func nineAndNineFifteenClash() {
        let nine = UUID(), quarterPast = UUID(), halfPast = UUID()
        #expect(DayHalfPlanner.sameTimeClashes(
            in: [nine: at(9, 0), quarterPast: at(9, 15)], using: calendar
        ) == [nine, quarterPast])
        #expect(DayHalfPlanner.sameTimeClashes(in: [nine: at(9, 0), halfPast: at(9, 30)], using: calendar).isEmpty)
    }

    @Test("The day badge counts a run of overlapping times as one clash")
    func badgeCountsOverlappingRuns() {
        let clashes = WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [540, 555, 600, 660])
        #expect(clashes == WeekDayColumn.DayClashes(children: 0, sameTimes: 1, sameTimeLessons: 2))
        #expect(clashes.plainHelp == "Two lessons overlap. Change one of the times.")
    }

    @Test("The legend names the clash as the badge does: lessons at overlapping times")
    func legendMatchesTheBadge() {
        let badge = WeekDayColumn.DayClashes(children: 0, sameTimes: 1, sameTimeLessons: 2).timedParts
        #expect(badge == ["2 lessons at overlapping times"])
        #expect(badge[0].hasSuffix(WeekPlanLegend.overlappingTimes.lowercased()))
    }
}
