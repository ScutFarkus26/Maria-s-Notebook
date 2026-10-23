import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Plan - Schedules, decision 14: Today's Schedule section reads the Schedules
/// timetable. The day's blocks from every lane in time order, a turn once
/// (as "Your turn in the adolescent room"), changes marked, a person out on
/// a line of her own, and never the guide's lessons, which the agenda lists.
/// The section's gate is pinned in `TodaySectionVisibilityTests`.
@Suite("Today's Schedule section")
@MainActor
struct TodayScheduleSectionTests {
    private typealias Support = TimetableTestSupport

    /// Sunday 18 October 2026, then the week after it.
    private func day(_ offset: Int) throws -> Date {
        try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 18 + offset, hour: 10)))
    }

    // MARK: - Weekday(date:)

    @Test("Weekday(date:) names the day of the week a date falls on")
    func weekdayFromDate() throws {
        let week: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        for (offset, expected) in week.enumerated() {
            #expect(Weekday(date: try day(offset)) == expected)
        }
        // Late in the evening is still that day in the calendar given.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let mondayNight = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23)))
        #expect(Weekday(date: mondayNight, calendar: newYork) == .monday)
    }

    // MARK: - Rows

    @Test("The day's blocks in time order: a turn once, others' blocks with who, changes marked, no lessons")
    func rowsFromTheResolvedDay() throws {
        let monday = Support.monday
        let math = Support.block(
            Support.adolescentRoom, .monday, Support.minutes(10, 30), 75, "Math", teacher: Support.guide
        )
        let humanities = Support.block(
            Support.adolescentRoom, .monday, Support.minutes(9), 60, "Humanities", teacher: Support.devora
        )
        let group = Support.block(Support.devora, .monday, Support.minutes(13), 30, "Chumash", children: [Support.lucy])
        let recess = Support.block(Support.ourClass, .monday, Support.minutes(11), 30, "Recess")
        let early = Support.block(Support.ourClass, oneOff: monday, Support.minutes(14), 15, "Early dismissal")
        let changed = TimetableChangeSnapshot(
            day: monday, kind: .changed, blockID: recess.id,
            values: TimetableBlockValues(startMinute: Support.minutes(11, 15), lengthMinutes: 30, title: "Recess")
        )
        let lesson = ScheduleLessonSnapshot(
            id: UUID(), title: "Long Division", half: .morning, studentIDs: [Support.lucy]
        )
        let resolved = Support.resolve(
            monday, blocks: [math, humanities, group, recess, early], changes: [changed], lessons: [lesson]
        )

        let rows = TodayScheduleRows.rows(resolved) { $0 == Support.lucy ? "Lucy T" : nil }

        #expect(rows.map(\.title) == [
            "Humanities", "Your turn in the adolescent room · Math", "Recess", "Chumash", "Early dismissal"
        ])
        #expect(rows.map(\.time) == ["9:00–10:00", "10:30–11:45", "11:15–11:45", "1:00–1:30", "2:00–2:15"])
        #expect(rows.map(\.mark) == [nil, nil, .changed, nil, .todayOnly])
        #expect(rows.first?.detail == "Adolescent room · Morah Devora")
        #expect(rows[3].detail == "Morah Devora · Lucy T")
        #expect(!rows.contains { $0.title.contains("Long Division") })
    }

    @Test("A person out is a row of her own, and her turn reads that she is out")
    func personOut() throws {
        let monday = Support.monday
        let humanities = Support.block(
            Support.adolescentRoom, .monday, Support.minutes(9), 60, "Humanities", teacher: Support.devora
        )
        let group = Support.block(Support.devora, .monday, Support.minutes(13), 30, "Chumash")
        let out = TimetableChangeSnapshot(day: monday, kind: .out, laneID: Support.devora.id)
        let rows = TodayScheduleRows.rows(Support.resolve(monday, blocks: [humanities, group], changes: [out]))

        #expect(rows.map(\.title) == ["Morah Devora is out today", "Humanities"])
        #expect(rows.first?.mark == .out)
        #expect(rows.last?.detail == "Adolescent room · Morah Devora is out")
    }

    @Test("No school: no rows")
    func noSchool() {
        let block = Support.block(Support.ourClass, .monday, Support.minutes(9), 60, "Work cycle")
        #expect(TodayScheduleRows.rows(Support.resolve(Support.monday, blocks: [block], isSchoolDay: false)).isEmpty)
    }

    // MARK: - On Today

    @Test("Today's reload reads the timetable, and a block added elsewhere reloads Today")
    func todayReadsAndFollowsTheTimetable() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let lanes = TimetableService.makeStarterLanes(in: context)
        let room = lanes[1]
        let guideID = try #require(lanes[2].id)
        TimetableService.addBlock(
            TimetableBlockValues(startMinute: 10 * 60 + 30, lengthMinutes: 75, title: "Math", teacherLaneID: guideID),
            to: room, on: [.monday], in: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = TodayViewModel(context: context, date: Support.monday)
        viewModel.reload()
        #expect(viewModel.scheduleRows.map(\.title) == ["Your turn in the adolescent room · Math"])

        viewModel.date = Support.tuesday
        viewModel.reload()
        #expect(viewModel.scheduleRows.isEmpty)

        // An assembly added on Tuesday on the Schedules page of another window (or another device).
        let afterFirst = viewModel.reloadCount
        let laneID = try #require(lanes[0].id).uuidString
        let tuesday = Support.tuesday
        let other = stack.newBackgroundContext()
        other.performAndWait {
            let block = CDTimetableBlock(context: other)
            block.laneID = laneID
            block.onDay = tuesday
            block.startMinute = 10 * 60
            block.lengthMinutes = 30
            block.title = "Assembly"
            _ = other.safeSave()
        }
        viewModel.scheduleReloadIfInputsChanged()
        await viewModel.reloadTask?.value
        #expect(viewModel.reloadCount == afterFirst + 1)
        #expect(viewModel.scheduleRows.map(\.title) == ["Assembly"])
        #expect(viewModel.scheduleRows.first?.mark == .todayOnly)
    }
}
