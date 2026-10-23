import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Plan - Schedules, Phase 2A: where things go on the Schedules page and the
/// words on them, without a screen, and the Sample Class's timetable.
@Suite("Schedules page layout and words")
@MainActor
struct ScheduleLayoutTests {
    private typealias Support = TimetableTestSupport

    // MARK: - Words

    @Test("A room reads naturally in a sentence, whatever case it was typed in")
    func roomInASentence() {
        #expect(ScheduleText.inRoom("Adolescent room") == "in the adolescent room")
        #expect(ScheduleText.inRoom("Our class") == "in our class")
        #expect(ScheduleText.inRoom("Beit Midrash") == "in the Beit Midrash")
        #expect(ScheduleText.inRoom("  ") == "in the other room")
        #expect(ScheduleText.turnTitle(room: "Adolescent room", title: "Math") == "In the adolescent room · Math")
        #expect(ScheduleText.turnTitle(room: "Adolescent room", title: " ") == "In the adolescent room")
        #expect(ScheduleText.yourTurnTitle(room: "Adolescent room", title: "") == "Your turn in the adolescent room")
    }

    @Test("The change chip, the week's chip, children's names and who teaches")
    func chipsAndNames() {
        #expect(ScheduleText.changeChip(count: 0, isToday: true) == nil)
        #expect(ScheduleText.changeChip(count: 1, isToday: true) == "1 change today")
        #expect(ScheduleText.changeChip(count: 3, isToday: false) == "3 changes")
        #expect(ScheduleText.weekChangeChip(days: 0) == nil)
        #expect(ScheduleText.weekChangeChip(days: 2) == "2 days changed")

        let names = ["A": "Ari C", "B": "Bea D", "C": "Cy E", "D": "Dov F", "E": "Eve G"]
        #expect(ScheduleText.children(["A", "Z", "B"]) { names[$0] } == "Ari C, Bea D")
        #expect(ScheduleText.children(["Z"]) { names[$0] } == nil)
        #expect(ScheduleText.children(["A", "B", "C", "D", "E"]) { names[$0] } == "Ari C, Bea D, Cy E and 2 more")

        let lanes = [Support.devora.id: Support.devora]
        let byLane = TimetableBlockValues(startMinute: 0, teacherLaneID: Support.devora.id)
        let byName = TimetableBlockValues(startMinute: 0, teacherName: " Mr. Adler ")
        #expect(ScheduleText.teacher(of: byLane, lanes: lanes) == "Morah Devora")
        #expect(ScheduleText.teacher(of: byName, lanes: lanes) == "Mr. Adler")
        #expect(ScheduleText.teacher(of: TimetableBlockValues(startMinute: 0), lanes: lanes) == nil)
        #expect(ScheduleBlockSheet.lengthText(45) == "45 min")
        #expect(ScheduleBlockSheet.lengthText(60) == "1 hr")
        #expect(ScheduleBlockSheet.lengthText(135) == "2 hr 15 min")
    }

    // MARK: - The Day view

    @Test("The day spans whole hours around its items, never less than 8:00 to 3:00")
    func range() {
        let empty = Support.resolve(Support.monday, blocks: [])
        #expect(ScheduleGridLayout.range(of: empty) == 480...900)
        let early = Support.block(Support.ourClass, .monday, Support.minutes(7, 40), 20, "Drop-off")
        let late = Support.block(Support.ourClass, .monday, Support.minutes(15, 30), 45, "Clubs")
        #expect(ScheduleGridLayout.range(of: Support.resolve(Support.monday, blocks: [early, late])) == 420...1020)
    }

    @Test("Items that overlap share the lane in columns; the next one after them gets the whole lane")
    func overlapsShareColumns() throws {
        let first = Support.block(Support.devora, .monday, Support.minutes(9), 60, "Group A")
        let second = Support.block(Support.devora, .monday, Support.minutes(9, 30), 60, "Group B")
        let third = Support.block(Support.devora, .monday, Support.minutes(11), 30, "Group C")
        let day = Support.resolve(Support.monday, blocks: [first, second, third])
        let items = try #require(day.lane(Support.devora.id)?.items)
        let placed = ScheduleGridLayout.place(items, from: 8 * 60)

        #expect(placed.map(\.column) == [0, 1, 0])
        #expect(placed.map(\.columns) == [2, 2, 1])
        #expect(placed.first?.top == 120)
        #expect(placed.first?.height == 120)
        // A five-minute block is still tall enough to read.
        let short = Support.block(Support.ourClass, .monday, Support.minutes(9), 5, "Line up")
        let shortDay = Support.resolve(Support.monday, blocks: [short])
        let shortItem = try #require(shortDay.lane(Support.ourClass.id)?.items.first)
        #expect(ScheduleGridLayout.height(of: shortItem) == ScheduleGridLayout.minimumBlockHeight)
    }

    @Test("A half's list moves down past the guide's turn at its hour instead of sharing the lane")
    func halfListMovesPastTheTurn() throws {
        let math = Support.block(
            Support.adolescentRoom, .monday, Support.minutes(9), 60, "Math", teacher: Support.guide
        )
        let lesson = ScheduleLessonSnapshot(id: UUID(), title: "Fractions", half: .morning, studentIDs: [Support.lucy])
        let day = Support.resolve(Support.monday, blocks: [math], lessons: [lesson])
        let items = try #require(day.lane(Support.guide.id)?.items)
        let placed = ScheduleGridLayout.place(items, from: 8 * 60)

        #expect(placed.map(\.columns) == [1, 1])
        let turn = try #require(placed.first)
        let list = try #require(placed.last)
        guard case .halfList = list.item.kind else {
            Issue.record("The morning list should come after the turn")
            return
        }
        #expect(list.top >= turn.top + turn.height)
        #expect(ScheduleGridLayout.contentHeight(range: 480...900, placed: [placed]) == 840)
    }

    // MARK: - The iPhone list

    @Test("The list has every lane in time order with a turn once; one lane's list keeps its turns")
    func listRows() {
        let math = Support.block(
            Support.adolescentRoom, .monday, Support.minutes(10, 30), 75, "Math", teacher: Support.guide
        )
        let recess = Support.block(Support.ourClass, .monday, Support.minutes(11), 30, "Recess")
        let lesson = ScheduleLessonSnapshot(id: UUID(), title: "Fractions", half: .morning, studentIDs: [Support.lucy])
        let day = Support.resolve(Support.monday, blocks: [math, recess], lessons: [lesson])

        let all = ScheduleDayRows.rows(day)
        #expect(all.map(\.lane.name) == ["Danny", "Adolescent room", "Our class"])
        #expect(all.map(\.item.startMinute) == [Support.minutes(9), Support.minutes(10, 30), Support.minutes(11)])

        let guideOnly = ScheduleDayRows.rows(day, lane: Support.guide.id)
        #expect(guideOnly.count == 2)
        guard case .turn = guideOnly.last?.item.kind else {
            Issue.record("The guide's own list should keep his turn")
            return
        }
        #expect(ScheduleDayRows.row(holdingLesson: lesson.id, in: day)?.lane.id == Support.guide.id)
        #expect(ScheduleDayRows.row(holdingLesson: UUID(), in: day) == nil)
    }

    @Test("An adolescents-only lesson is found inside the turn it was placed in")
    func lessonInTurn() throws {
        let math = Support.block(
            Support.adolescentRoom, .monday, Support.minutes(9), 60, "Math", teacher: Support.guide
        )
        let lesson = ScheduleLessonSnapshot(id: UUID(), title: "Algebra", half: .morning, studentIDs: [Support.ari])
        let day = Support.resolve(Support.monday, blocks: [math], lessons: [lesson])
        let row = try #require(ScheduleDayRows.row(holdingLesson: lesson.id, in: day))
        #expect(row.lane.id == Support.guide.id)
        guard case .turn(let block) = row.item.kind else {
            Issue.record("The lesson should be in the guide's turn")
            return
        }
        #expect(block.lessons.map(\.id) == [lesson.id])
    }

    // MARK: - The Sample Class

    @Test("The Sample Class gets four lanes, a week with a shorter Friday, turns and one change, once")
    func sampleClassTimetable() throws {
        let context = try Support.context()
        let now = Support.time(Support.monday, 8)
        try SampleClassroomSeeder.seedTimetableIfNeeded(lessons: [], in: context, now: now, calendar: Support.calendar)
        #expect(CoreDataTestHelpers.save(context))

        let monday = Support.resolveStored(Support.monday, in: context)
        #expect(monday.lanes.map(\.lane.name).last == "Morah Rivka")
        #expect(monday.lanes.count == 4)
        #expect(monday.changeCount == 1)
        let guide = try #require(monday.lanes.first { $0.lane.isGuide })
        #expect(guide.items.compactMap { $0.block?.values.title } == ["Math"])
        let rivka = try #require(monday.lanes.last)
        #expect(rivka.items.compactMap { $0.block?.values.title } == [
            "Chumash group", "Hebrew reading", "Kodesh", "Torah study"
        ])
        let friday = Support.resolveStored(Support.friday, in: context)
        let fridayEnd = friday.lanes.first?.items.compactMap { $0.endMinute }.max()
        #expect(fridayEnd == Support.minutes(12, 45))

        try SampleClassroomSeeder.seedTimetableIfNeeded(lessons: [], in: context, now: now, calendar: Support.calendar)
        #expect(TimetableService.lanes(in: context).count == 4)
    }
}
