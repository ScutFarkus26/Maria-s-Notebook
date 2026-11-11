import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Covers start times on scheduled lessons (plan "Lesson times on cards",
/// Phase 1): how a stored moment reads as a set time or an ordering slot
/// (decision 4), which paths keep a time and which remove it (decision 5), the
/// shared order for a day (decision 6), and same-time clashes (decision 7).
@Suite("Lesson times")
@MainActor
struct LessonTimeTests {

    let calendar = AppCalendar.shared

    func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let noon = DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)
        return calendar.startOfDay(for: calendar.date(from: noon)!)
    }

    /// Wednesday 16 September 2026, a school day.
    var wednesday: Date { day(2026, 9, 16) }

    func time(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, on base: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: base)!
    }

    func clock(_ date: Date?) -> [Int] {
        guard let date else { return [] }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return [parts.hour ?? -1, parts.minute ?? -1, parts.second ?? -1]
    }

    func planned(at date: Date?, in context: NSManagedObjectContext) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.id = UUID()
        assignment.createdAt = wednesday
        if let date { assignment.schedule(for: date) }
        return assignment
    }

    // MARK: - Decision 4: how a stored moment reads

    @Test("Every row of the reading table")
    func readingTable() {
        let day = wednesday
        // Midnight: a morning slot; 0:00:59 is a set midnight.
        #expect(DayHalfPlanner.moment(of: day) == .half(.morning))
        #expect(DayHalfPlanner.moment(of: time(0, 0, 59, on: day)) == .time(time(0, 0, 59, on: day)))
        // Base hour, minute 0, second 0–58: a slot in that half.
        #expect(DayHalfPlanner.moment(of: time(9, 0, 0, on: day)) == .half(.morning))
        #expect(DayHalfPlanner.moment(of: time(9, 0, 58, on: day)) == .half(.morning))
        #expect(DayHalfPlanner.moment(of: time(14, 0, 0, on: day)) == .half(.afternoon))
        #expect(DayHalfPlanner.moment(of: time(14, 0, 58, on: day)) == .half(.afternoon))
        // Base hour, minute 0, second 59: the marker for exactly that hour.
        #expect(DayHalfPlanner.moment(of: time(9, 0, 59, on: day)) == .time(time(9, 0, 59, on: day)))
        #expect(DayHalfPlanner.moment(of: time(14, 0, 59, on: day)) == .time(time(14, 0, 59, on: day)))
        // Any other time on the minute: a set time.
        #expect(DayHalfPlanner.moment(of: time(10, 30, on: day)) == .time(time(10, 30, on: day)))
        #expect(DayHalfPlanner.moment(of: time(8, 45, on: day)) == .time(time(8, 45, on: day)))
        #expect(DayHalfPlanner.moment(of: time(13, 0, on: day)) == .time(time(13, 0, on: day)))
        // Any other time off the minute: a slot in its half.
        #expect(DayHalfPlanner.moment(of: time(10, 30, 1, on: day)) == .half(.morning))
        #expect(DayHalfPlanner.moment(of: time(14, 15, 3, on: day)) == .half(.afternoon))
    }

    @Test("A slot pushed one second below a timed lesson reads as a slot")
    func pushedSlotIsASlot() {
        let pushed = time(10, 30, 1, on: wednesday)
        #expect(DayHalfPlanner.keptTime(of: pushed) == nil)
        #expect(DayHalfPlanner.setMinute(of: pushed) == nil)
        #expect(!DayHalfPlanner.isSetTime(pushed))
    }

    @Test("9:00 and 2:00 round trip as set times")
    func exactBaseHoursRoundTrip() {
        for hour in [0, 9, 14] {
            let set = DayHalfPlanner.settingTime(hour: hour, minute: 0, on: wednesday)
            #expect(clock(set) == [hour, 0, 59])
            #expect(DayHalfPlanner.isSetTime(set))
            #expect(DayHalfPlanner.setMinute(of: set) == hour * 60)
            #expect(MCPNotebookTools.timeString(set) == String(format: "%02d:00", hour))
        }
    }

    @Test("Any other time is written on the minute and reads back as itself")
    func otherTimesRoundTrip() {
        for (hour, minute) in [(8, 45), (10, 30), (11, 0), (13, 0), (15, 15), (9, 15), (14, 45)] {
            let set = DayHalfPlanner.settingTime(hour: hour, minute: minute, on: wednesday)
            #expect(clock(set) == [hour, minute, 0])
            #expect(DayHalfPlanner.setMinute(of: set) == hour * 60 + minute)
            #expect(calendar.isDate(set, inSameDayAs: wednesday))
        }
    }

    @Test("Slot ranks stop at 58, so a long half never writes the marker")
    func slotRanksStopAt58() {
        let placements = (0..<80).map { _ in DayHalfPlanner.Placement(id: UUID(), period: .morning) }
        let times = DayHalfPlanner.times(for: placements, on: wednesday, using: calendar, spacingSeconds: 1)
        #expect(times.values.allSatisfy { DayHalfPlanner.moment(of: $0) == .half(.morning) })
        #expect(times[placements[58].id] == time(9, 0, 58, on: wednesday))
        #expect(times[placements[79].id] == time(9, 0, 58, on: wednesday))
        #expect(DayHalfPlanner.slot(70, in: .afternoon, on: wednesday) == time(14, 0, 58, on: wednesday))
    }

    @Test("Removing a time keeps the half and goes to its last slot")
    func removingATime() {
        let morning = DayHalfPlanner.removingTime(from: time(10, 30, on: wednesday))
        #expect(morning == time(9, 0, DayHalfPlanner.lastSlotRank, on: wednesday))
        let two = DayHalfPlanner.settingTime(hour: 14, minute: 0, on: wednesday)
        let afternoon = DayHalfPlanner.removingTime(from: two)
        #expect(afternoon == time(14, 0, DayHalfPlanner.lastSlotRank, on: wednesday))
        #expect(DayHalfPlanner.moment(of: afternoon) == .half(.afternoon))
        // A slot comes back as it was.
        let slot = time(9, 0, 3, on: wednesday)
        #expect(DayHalfPlanner.removingTime(from: slot) == slot)
    }

    // MARK: - Re-basing onto another day

    @Test("Re-basing keeps the clock time, across both daylight-saving Sundays")
    func rebasingAcrossDaylightSaving() {
        // Friday before each change, onto the Sunday of the change and the
        // Monday after it.
        let cases: [(from: Date, onto: [Date])] = [
            (day(2026, 10, 30), [day(2026, 11, 1), day(2026, 11, 2)]),
            (day(2027, 3, 12), [day(2027, 3, 14), day(2027, 3, 15)])
        ]
        for (from, targets) in cases {
            for (hour, minute) in [(9, 0), (10, 30), (14, 0), (13, 15)] {
                let set = DayHalfPlanner.settingTime(hour: hour, minute: minute, on: from)
                for target in targets {
                    let moved = DayHalfPlanner.rebasing(set, onto: target)
                    #expect(calendar.isDate(moved, inSameDayAs: target))
                    #expect(DayHalfPlanner.setMinute(of: moved) == hour * 60 + minute)
                    #expect(clock(moved) == clock(set))
                }
            }
        }
    }

    @Test("A kept time is returned on the day being numbered, not its old day")
    func timesRebaseAKeptTime() {
        let timed = UUID(), slot = UUID()
        let oldDay = DayHalfPlanner.settingTime(hour: 10, minute: 30, on: day(2026, 9, 14))
        let times = DayHalfPlanner.times(
            for: [
                .init(id: slot, period: .morning),
                .init(id: timed, period: .morning, keptTime: oldDay)
            ],
            on: wednesday,
            using: calendar,
            spacingSeconds: 1
        )
        #expect(times[timed] == time(10, 30, on: wednesday))
        #expect(times[slot] == time(9, 0, 0, on: wednesday))
    }

    // MARK: - Decision 5: drops

    @Test("A timed card dropped on another day keeps its time and half wherever it lands")
    func droppedTimedCardKeepsItsTime() {
        let morningSlot = UUID(), afternoonSlot = UUID(), dropped = UUID()
        let scheduled: [UUID: Date] = [
            morningSlot: time(9, 0, 0, on: wednesday),
            afternoonSlot: time(14, 0, 0, on: wednesday),
            // Set for 10:30 on Monday, dragged here.
            dropped: DayHalfPlanner.settingTime(hour: 10, minute: 30, on: day(2026, 9, 14))
        ]
        // Dropped under the afternoon card, at the end of the column.
        let placements = DayHalfPlanner.placementsAfterDrop(
            ordering: [morningSlot, afternoonSlot, dropped], dropped: [dropped], scheduledFor: scheduled
        )
        #expect(placements.first { $0.id == dropped }?.period == .morning)
        let times = DayHalfPlanner.times(for: placements, on: wednesday, using: calendar, spacingSeconds: 1)
        #expect(times[dropped] == time(10, 30, on: wednesday))
        #expect(times[morningSlot] == time(9, 0, 0, on: wednesday))
        #expect(times[afternoonSlot] == time(14, 0, 0, on: wednesday))
    }

    @Test("An exact 9:00 dropped among afternoon cards stays 9:00")
    func droppedNineOClockStays() {
        let afternoon = UUID(), dropped = UUID()
        let nine = DayHalfPlanner.settingTime(hour: 9, minute: 0, on: day(2026, 9, 15))
        let placements = DayHalfPlanner.placementsAfterDrop(
            ordering: [afternoon, dropped],
            dropped: [dropped],
            scheduledFor: [afternoon: time(14, 0, 0, on: wednesday), dropped: nine]
        )
        let times = DayHalfPlanner.times(for: placements, on: wednesday, using: calendar, spacingSeconds: 1)
        #expect(times[dropped] == DayHalfPlanner.settingTime(hour: 9, minute: 0, on: wednesday))
        #expect(DayHalfPlanner.setMinute(of: times[dropped]) == 9 * 60)
    }

    @Test("An untimed card still takes the half of the card it lands under")
    func droppedUntimedCardInherits() {
        let morning = UUID(), afternoon = UUID(), dropped = UUID()
        let placements = DayHalfPlanner.placementsAfterDrop(
            ordering: [morning, afternoon, dropped],
            dropped: [dropped],
            scheduledFor: [
                morning: time(9, 0, 0, on: wednesday),
                afternoon: time(14, 0, 0, on: wednesday),
                dropped: time(9, 0, 4, on: day(2026, 9, 14))
            ]
        )
        #expect(placements.map(\.period) == [.morning, .afternoon, .afternoon])
        #expect(placements.allSatisfy { $0.keptTime == nil })
        let times = DayHalfPlanner.times(for: placements, on: wednesday, using: calendar, spacingSeconds: 1)
        #expect(times[dropped] == time(14, 0, 1, on: wednesday))
    }

    @Test("Reordering the untimed cards leaves a timed card where it is")
    func reorderAroundATimedCard() {
        let timed = UUID(), first = UUID(), second = UUID()
        let tenThirty = time(10, 30, on: wednesday)
        let placements = DayHalfPlanner.placementsAfterDrop(
            ordering: [timed, second, first],
            dropped: [second],
            scheduledFor: [timed: tenThirty, first: time(9, 0, 0, on: wednesday), second: time(9, 0, 1, on: wednesday)]
        )
        let times = DayHalfPlanner.times(for: placements, on: wednesday, using: calendar, spacingSeconds: 1)
        #expect(times[timed] == tenThirty)
        // Slots count from the base hour, never on from the 10:30.
        #expect(times[second] == time(9, 0, 0, on: wednesday))
        #expect(times[first] == time(9, 0, 1, on: wednesday))
    }

    @Test("Choosing the other half removes a set time; the same half changes nothing")
    func halfChoiceOnATime() {
        let tenThirty = time(10, 30, on: wednesday)
        #expect(DayPeriod.morning.applied(to: tenThirty) == tenThirty)
        let flipped = DayPeriod.afternoon.applied(to: tenThirty)
        #expect(flipped == time(14, 0, DayHalfPlanner.lastSlotRank, on: wednesday))
        #expect(!DayHalfPlanner.isSetTime(flipped))
        // Not 2:30, which is what carrying the minutes across used to make.
        #expect(clock(flipped) != [14, 30, 0])
    }

    @Test("Move All Forward keeps a set time, the 9:00 marker included")
    func forwardShiftKeepsTimes() {
        let thursday = day(2026, 9, 17)
        for set in [
            DayHalfPlanner.settingTime(hour: 9, minute: 0, on: wednesday),
            DayHalfPlanner.settingTime(hour: 10, minute: 30, on: wednesday)
        ] {
            let moved = CalendarForwardShiftService.preservingTimeOfDay(from: set, onto: thursday, using: calendar)
            #expect(moved == DayHalfPlanner.rebasing(set, onto: thursday))
            #expect(DayHalfPlanner.setMinute(of: moved) == DayHalfPlanner.setMinute(of: set))
        }
        // And a slot stays a slot with its rank.
        let slot = CalendarForwardShiftService.preservingTimeOfDay(
            from: time(9, 0, 4, on: wednesday), onto: thursday, using: calendar
        )
        #expect(DayHalfPlanner.moment(of: slot) == .half(.morning))
    }

    @Test("Scheduling a selection today writes slots, not times, however long the selection")
    func readyToPresentSpacingIsSlots() {
        // `ReadyToPresentSection.scheduleSelectionToday` writes
        // `DayHalfPlanner.slot(index, in: .morning, on: today)`: a second
        // apart from 9:00:00, stopping at the last rank rather than reaching
        // 9:00:59 (an exact 9:00) or 9:01:00 (a set 9:01) at the 60th lesson.
        for index in 0..<80 {
            let written = DayHalfPlanner.slot(index * UIConstants.scheduleSpacingSeconds, in: .morning, on: wednesday)
            #expect(DayHalfPlanner.moment(of: written) == .half(.morning))
        }
    }

    // MARK: - Decision 7: same-time clashes

    @Test("Lessons at the same start minute clash, whoever the children; slots never do")
    func sameTimeClashes() {
        let first = UUID(), second = UUID(), eleven = UUID(), nine = UUID(), slot = UUID(), slotTwo = UUID()
        let clashes = DayHalfPlanner.sameTimeClashes(in: [
            first: time(10, 30, on: wednesday),
            second: time(10, 30, on: wednesday),
            eleven: time(11, 0, on: wednesday),
            // An exact 9:00 and a 9:00 slot are not the same start time.
            nine: DayHalfPlanner.settingTime(hour: 9, minute: 0, on: wednesday),
            slot: time(9, 0, 0, on: wednesday),
            slotTwo: time(9, 0, 0, on: wednesday)
        ])
        #expect(clashes == [first, second])
    }
}
