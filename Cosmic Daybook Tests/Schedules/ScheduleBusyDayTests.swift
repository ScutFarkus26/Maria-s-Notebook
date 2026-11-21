import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The day's one busy picture (plan "Domain logic fixes", R16 and A7): the
/// guide's turns, Out Today, children leaving early or absent, lessons that
/// overlap, and blocks that overlap, as the Schedules warnings and the
/// planner's away times (`AwayDay`) both read them.
@Suite("Schedules: the day's busy picture")
@MainActor
struct ScheduleBusyDayTests {

    private typealias Support = TimetableTestSupport

    private let ourClass = Support.ourClass
    private let room = Support.adolescentRoom
    private let guide = Support.guide
    private let devora = Support.devora
    private let nicole = TimetableLaneSnapshot(name: "Miss Nicole", kind: .person, sortOrder: 4)
    private var lanes: [TimetableLaneSnapshot] { [ourClass, room, guide, devora, nicole] }

    private let lucy = Support.lucy
    private let ari = Support.ari
    private let bea = Support.bea

    private func minutes(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    private func lesson(_ title: String, at minute: Int?, half: ScheduleDayHalf = .morning, children: [String])
        -> ScheduleLessonSnapshot {
        ScheduleLessonSnapshot(id: UUID(), title: title, half: half, minute: minute, studentIDs: children)
    }

    private func resolve(
        _ blocks: [TimetableBlockSnapshot],
        lanes: [TimetableLaneSnapshot]? = nil,
        changes: [TimetableChangeSnapshot] = [],
        lessons: [ScheduleLessonSnapshot] = [],
        away: [ScheduleChildAway] = []
    ) -> ScheduleDay {
        ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: Support.monday, lanes: lanes ?? self.lanes, blocks: blocks, changes: changes, lessons: lessons,
            studentLevels: Support.levels, childrenAway: away, calendar: Support.calendar
        ))
    }

    private func out(_ lane: TimetableLaneSnapshot) -> TimetableChangeSnapshot {
        TimetableChangeSnapshot(day: Support.monday, kind: .out, laneID: lane.id)
    }

    // MARK: - Free times and the guide's turns

    @Test("Free times keep clear of the guide's turn, except for a lesson for adolescents only")
    func freeTimesAvoidTheGuidesTurn() {
        let turn = Support.block(room, .monday, minutes(10), 45, "Turn", teacher: guide)
        let day = AwayTimes.day(from: resolve([turn]), adolescentIDs: [ari, bea])

        #expect(day.freeStarts(children: [lucy], ownStarts: []) == [minutes(8, 45), minutes(10, 45)])
        #expect(day.turnClash(children: [lucy], start: minutes(10, 15))?.blockID == turn.id)
        #expect(day.turnClash(children: [ari, bea], start: minutes(10, 15)) == nil)
        #expect(day.freeStarts(children: [ari, bea], ownStarts: []).isEmpty, "nothing busy for them")
        #expect(day.freeHalves(children: [lucy]) == [.afternoon])

        let note = AwayOnCards.note(
            in: day, children: [lucy], setMinute: minutes(10, 15), half: .morning, name: { _ in nil }
        )
        #expect(note == AwayOnCards.Note(line: "During your turn in Adolescent room (10:00–10:45)", isClash: true))
    }

    @Test("A lesson that overlaps the guide's turn warns on Schedules too, not only one starting in it")
    func lessonOverlappingTurnWarns() {
        let turn = Support.block(room, .monday, minutes(10), 45, "Turn", teacher: guide)
        let early = lesson("Fractions", at: minutes(9, 45), children: [lucy])
        let warnings = resolve([turn], lessons: [early]).warnings
        #expect(warnings.contains { if case .lessonDuringTurn = $0 { true } else { false } })
    }

    // MARK: - Out Today

    @Test("Out Today sets the guide's lessons aside with one warning, and offers no free time")
    func outTodaySetsLessonsAside() {
        let group = Support.block(devora, .monday, minutes(9), 30, "Reading", children: [lucy])
        let lessons = [
            lesson("Fractions", at: minutes(9), children: [lucy]),
            lesson("Verbs", at: nil, children: [ari])
        ]
        let day = resolve([group], changes: [out(guide)], lessons: lessons)

        #expect(day.warnings == [.guideOut(lessonCount: 2)])
        #expect(day.warnings.first?.text(name: { _ in nil }) == "You're out; 2 lessons are planned.")
        #expect(day.lane(guide.id)?.items.isEmpty == true)
        #expect(Set(day.setAsideLessons.compactMap(\.snapshot.title)) == ["Fractions", "Verbs"])

        let away = AwayTimes.day(from: day)
        #expect(away.guideIsOut)
        #expect(away.freeStarts(children: [lucy], ownStarts: []).isEmpty)
        let note = AwayOnCards.note(in: away, children: [ari], setMinute: nil, half: .morning, name: { _ in nil })
        #expect(note == AwayOnCards.Note(line: AwayText.outLine, isClash: true))
    }

    // MARK: - Lessons and blocks that overlap

    @Test("Two of the guide's lessons at 9:00 and 9:15 clash; at 9:00 and 9:30 they don't")
    func lessonsLessThanALessonApartClash() {
        // Children of our class (an adolescents-only lesson warns about his turn as well).
        let first = lesson("Fractions", at: minutes(9), children: [lucy])
        let second = lesson("Verbs", at: minutes(9, 15), children: [UUID().uuidString])
        let clear = lesson("Maps", at: minutes(9, 30), children: [UUID().uuidString])
        let warnings = resolve([], lessons: [first, second]).warnings
        #expect(warnings == [.lessonsOverlap(
            first: .init(id: first.id, title: "Fractions", minute: minutes(9)),
            second: .init(id: second.id, title: "Verbs", minute: minutes(9, 15))
        )])
        #expect(warnings.first?.text(name: { _ in nil }) == "Fractions at 9:00 and Verbs at 9:15 overlap.")
        #expect(resolve([], lessons: [first, clear]).warnings.isEmpty)
    }

    @Test("A child in two 9:15 groups, and a person with two blocks at once, are warned about")
    func overlappingBlocksWarn() {
        let reading = Support.block(devora, .monday, minutes(9, 15), 30, "Reading", children: [lucy, ari])
        let math = Support.block(nicole, .monday, minutes(9, 15), 45, "Math", children: [lucy])
        let later = Support.block(devora, .monday, minutes(9, 30), 30, "Hebrew", children: [bea])
        let day = resolve([reading, math, later])

        let twoGroups = day.warnings.filter { if case .childInTwoBlocks = $0 { true } else { false } }
        #expect(twoGroups.count == 1)
        guard case let .childInTwoBlocks(child, first, second)? = twoGroups.first else {
            Issue.record("No warning for the child in two groups")
            return
        }
        #expect(child == lucy)
        #expect(Set([first.blockID, second.blockID]) == [reading.id, math.id])
        #expect(twoGroups.first?.text(name: { $0 == lucy ? "Lucy T" : nil })
            == "Lucy T is in two groups at once: Morah Devora's Reading 9:15–9:45 and "
                + "Miss Nicole's Math 9:15–10:00.")

        let doubleBooked = day.warnings.filter { if case .personInTwoBlocks = $0 { true } else { false } }
        #expect(doubleBooked.count == 1)
        guard case let .personInTwoBlocks(laneID, _, _, _)? = doubleBooked.first else { return }
        #expect(laneID == devora.id)
    }

    // MARK: - Children away from class

    @Test("A child leaving at 1:30 is away for a 1:45 lesson, and for one at 1:10 that runs past it")
    func childLeavingEarlyBlocksLaterLessons() {
        let leaving = ScheduleChildAway(studentID: lucy, fromMinute: minutes(13, 30))
        let late = lesson("Fractions", at: minutes(13, 45), half: .afternoon, children: [lucy])
        let before = lesson("Maps", at: minutes(13), half: .afternoon, children: [lucy])
        let day = resolve([], lessons: [late, before], away: [leaving])

        #expect(day.warnings == [.childAwayFromClass(
            studentID: lucy, fromMinute: minutes(13, 30), lessonID: late.id, half: .afternoon,
            lessonMinute: minutes(13, 45)
        )])
        #expect(day.warnings.first?.text(name: { _ in "Lucy T" })
            == "Lucy T leaves at 1:30, and is in your 1:45 lesson.")

        let away = AwayTimes.day(from: day)
        #expect(away.clashes(children: [lucy], start: minutes(13, 45)).map(\.block.reason) == [.leavingEarly])
        #expect(away.clashes(children: [lucy], start: minutes(13, 10)).count == 1)
        #expect(away.clashes(children: [lucy], start: minutes(13)).isEmpty)
        #expect(AwayText.clashLine(
            away.clashes(children: [lucy], start: minutes(13, 45)), start: minutes(13, 45), name: { _ in "Lucy T" }
        ) == "Lucy T leaves at 1:30")
    }

    @Test("Attendance gives the day's busy picture its children away, with no lanes set up at all")
    func attendanceReachesTheAwayTimes() throws {
        let context = try Support.context()
        let leaving = CDAttendanceRecord(context: context)
        leaving.studentID = lucy
        leaving.date = Support.monday
        leaving.statusRaw = AttendanceStatus.present.rawValue
        leaving.leavesAt = Support.time(Support.monday, 13, 30)
        let absent = CDAttendanceRecord(context: context)
        absent.studentID = bea
        absent.date = Support.monday
        absent.statusRaw = AttendanceStatus.absent.rawValue
        #expect(context.safeSave())

        let day = try #require(
            AwayTimes.days(from: Support.monday, through: Support.monday, in: context)[Support.monday]
        )
        #expect(day.clashes(children: [lucy], start: minutes(13, 45)).count == 1)
        #expect(day.clashes(children: [lucy], start: minutes(10)).isEmpty)
        #expect(day.freeHalves(children: [bea]).isEmpty)
        #expect(day.freeHalves(children: [lucy]) == [.morning])
        let note = AwayOnCards.note(
            in: day, children: [bea], setMinute: nil, half: .afternoon, name: { _ in "Bea R" }
        )
        #expect(note?.line == "Bea R is absent")
    }

    // MARK: - The adolescent room (A7)

    @Test("A room stored as the adolescent room holds the guide's turns, whatever its name")
    func storedAdolescentRoomHoldsTheTurns() {
        let upstairs = TimetableLaneSnapshot(name: "Upstairs", kind: .room, sortOrder: 1, isAdolescentRoom: true)
        let lanes = [ourClass, upstairs, guide]
        let inClass = Support.block(ourClass, .monday, minutes(9), 60, "Circle", teacher: guide)
        let turn = Support.block(upstairs, .monday, minutes(10), 60, "Turn", teacher: guide)
        let forAdolescents = lesson("Algebra", at: nil, children: [ari, bea])
        let day = resolve([inClass, turn], lanes: lanes, lessons: [forAdolescents])

        let upstairsBlock = day.lane(upstairs.id)?.items.compactMap(\.block).first
        #expect(upstairsBlock?.lessons.map(\.id) == [forAdolescents.id])
        #expect(day.lane(ourClass.id)?.items.compactMap(\.block).first?.lessons.isEmpty == true)

        let rows = TodayScheduleRows.rows(day)
        #expect(rows.contains { $0.title == ScheduleText.yourTurnTitle(room: "Upstairs", title: "Turn") })
        #expect(!rows.contains { $0.title == ScheduleText.yourTurnTitle(room: "Our class", title: "Circle") })
    }

    @Test("The starter lanes store the adolescent room as one")
    func starterLanesMarkTheAdolescentRoom() throws {
        let context = try Support.context()
        let lanes = TimetableService.makeStarterLanes(in: context)
        #expect(lanes.filter(\.isAdolescentRoom).map(\.name) == ["Adolescent room"])
        #expect(lanes.first { $0.isAdolescentRoom }?.kind == .room)
    }
}
