import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `AwayOnCardsTests`' store-backed half: how the strip loads the away times
/// for its window and follows a change in Schedules, and the lesson's sheet.
private typealias Days = TimetableTestSupport

extension AwayOnCardsTests {

    // MARK: - Loading for the strip

    /// A store with the starter lanes and Morah Devora's 9:50 group on Mondays.
    func timetable(_ kids: Class) throws -> CDTimetableBlock {
        TimetableService.makeStarterLanes(in: kids.context)
        let person = TimetableService.addPerson(named: "Morah Devora", in: kids.context)
        let blocks = TimetableService.addBlock(
            TimetableBlockValues(
                startMinute: minutes(9, 50), lengthMinutes: 30, title: "Chumash", studentIDs: [kids.lucy.uuidString]
            ),
            to: person, on: [.monday], in: kids.context
        )
        #expect(kids.context.safeSave())
        return try #require(blocks.first)
    }

    @Test("The strip loads every day of its window at once, a grown window too, and follows a group's change")
    func stripLoading() throws {
        let kids = try makeClass()
        let block = try timetable(kids)
        let window = [Days.monday, Days.tuesday]
        let loaded = WeekPlanSection.awayDays(for: window, in: kids.context, calendar: calendar)
        #expect(loaded[Days.monday]?.away(children: [kids.lucy.uuidString]).map(\.block.title) == ["Chumash"])
        #expect(loaded[Days.tuesday]?.isEmpty == true)
        #expect(loaded[Days.nextMonday] == nil, "not in the window yet")

        // The strip scrolls on and the window grows: the new Monday has its group.
        let grown = WeekPlanSection.awayDays(for: window + [Days.nextMonday], in: kids.context, calendar: calendar)
        #expect(grown[Days.nextMonday]?.isEmpty == false)

        // A one-day cancel in Schedules: read again, the group is gone that day.
        TimetableService.cancel(block, on: Days.monday, in: kids.context)
        #expect(kids.context.safeSave())
        let after = WeekPlanSection.awayDays(for: window, in: kids.context, calendar: calendar)
        #expect(after[Days.monday]?.isEmpty == true)
        #expect(WeekPlanSection.awayDays(for: [], in: kids.context, calendar: calendar).isEmpty)
    }

    @Test("The strip reloads on any change to lanes, groups or one-day changes, and the watch is allowed")
    func reloadSignals() {
        #expect(WeekPlanSection.awayEntityNames == ["TimetableLane", "TimetableBlock", "TimetableChange"])
        #expect(WeekPlanSection.awayEntityNames.isSubset(of: PersistentHistoryProcessor.presentationEntityNames))
        let first = WeekPlanSection.AwayKey(first: Days.monday, last: Days.friday, version: 0)
        #expect(first != WeekPlanSection.AwayKey(first: Days.monday, last: Days.friday, version: 1))
        #expect(first != WeekPlanSection.AwayKey(first: Days.monday, last: Days.nextMonday, version: 0))
    }

    // MARK: - The lesson's sheet

    @Test("The sheet reads one day for its roster: the picker's list and the clash line for its time")
    func sheet() throws {
        let kids = try makeClass()
        _ = try timetable(kids)
        let other = planned(at: at(11, 0), children: [kids.ora], in: kids.context)
        #expect(kids.context.safeSave())

        let info = ScheduledDateEdits.awayInfo(
            on: at(9, 45), children: [kids.lucy, kids.naomi], excluding: nil, in: kids.context, using: calendar
        )
        #expect(info.names[kids.lucy.uuidString.uppercased()] == "Lucy T")
        #expect(info.ownStarts == [minutes(11, 0)])
        let picker = try #require(info.picker(children: [kids.lucy]))
        #expect(picker.rows == ["9:50–10:20 · Lucy T · Morah Devora"])
        #expect(info.clashLine(children: [kids.lucy], at: minutes(9, 45)) == "Lucy T leaves at 9:50 for Morah Devora")
        #expect(info.clashLine(children: [kids.lucy], at: minutes(10, 20)) == nil)
        #expect(info.clashLine(children: [kids.lucy], at: nil) == nil, "no set time, no line on the sheet")
        #expect(info.clashLine(children: [kids.naomi], at: minutes(9, 45)) == nil)

        // The unsaved roster is what counts: without Lucy nobody is away.
        let without = ScheduledDateEdits.awayInfo(
            on: at(9, 45), children: [kids.naomi], excluding: nil, in: kids.context, using: calendar
        )
        #expect(without == .empty)
        #expect(ScheduledDateEdits.awayInfo(
            on: at(9, 45), children: [], excluding: nil, in: kids.context, using: calendar
        ) == .empty)
        _ = other
    }
}
