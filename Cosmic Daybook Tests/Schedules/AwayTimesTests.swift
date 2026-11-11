import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Who is away with a co-teacher, and when (`AwayTimes`, `AwayDay`,
/// `AwayText`): the 30-minute overlap rule, the free starts, which blocks
/// count, and every sentence (plan "Co-teacher times when scheduling",
/// decisions 2–8). Its own fixtures: made-up last names, never the roster's.
@Suite("Schedules: who is away with a co-teacher")
@MainActor
struct AwayTimesTests {

    private typealias Support = TimetableTestSupport

    // Lanes of our own, with Miss Nicole beside Morah Devora.
    private let ourClass = TimetableLaneSnapshot(name: "Our class", kind: .room, sortOrder: 0)
    private let room = TimetableLaneSnapshot(name: "Adolescent room", kind: .room, sortOrder: 1)
    private let guide = TimetableLaneSnapshot(name: "Danny", kind: .person, isGuide: true, sortOrder: 2)
    private let devora = TimetableLaneSnapshot(name: "Morah Devora", kind: .person, sortOrder: 3)
    private let nicole = TimetableLaneSnapshot(name: "Miss Nicole", kind: .person, sortOrder: 4)
    private var lanes: [TimetableLaneSnapshot] { [ourClass, room, guide, devora, nicole] }

    // Children, as the planner hands them over (mixed case on purpose).
    private let lucy = UUID().uuidString.lowercased()
    private let ora = UUID().uuidString
    private let leora = UUID().uuidString
    private let naomi = UUID().uuidString

    private var names: [String: String] {
        [lucy.uppercased(): "Lucy T", ora: "Ora P", leora: "Leora F", naomi: "Naomi F"]
    }

    private func name(_ id: String) -> String? { names[id.uppercased()] }

    private func minutes(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    private func block(
        _ lane: TimetableLaneSnapshot, _ start: Int, _ length: Int, _ title: String = "Group",
        children: [String], teacher: TimetableLaneSnapshot? = nil
    ) -> TimetableBlockSnapshot {
        TimetableBlockSnapshot(
            laneID: lane.id, weekday: .monday,
            values: TimetableBlockValues(
                startMinute: start, lengthMinutes: length, title: title, teacherLaneID: teacher?.id,
                studentIDs: children
            )
        )
    }

    private func awayDay(
        _ blocks: [TimetableBlockSnapshot],
        changes: [TimetableChangeSnapshot] = [],
        isSchoolDay: Bool = true
    ) -> AwayDay {
        let resolved = ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: Support.monday, lanes: lanes, blocks: blocks, changes: changes, isSchoolDay: isSchoolDay,
            calendar: Support.calendar
        ))
        return AwayTimes.day(from: resolved)
    }

    /// Monday as it really runs: Miss Nicole's Book Club, then two of Morah
    /// Devora's groups.
    private var realMonday: AwayDay {
        awayDay([
            block(nicole, minutes(9, 15), 30, "Book Club", children: [lucy, ora]),
            block(devora, minutes(9, 50), 30, "Chumash", children: [lucy]),
            block(devora, minutes(10, 40), 30, "Navi", children: [ora])
        ])
    }

    // MARK: - The overlap rule

    @Test("A lesson overlaps a group only inside its 30 minutes: never at either edge")
    func overlapEdges() {
        let group = TimetableBlockValues(startMinute: minutes(9, 50), lengthMinutes: 30)
        #expect(LessonLength.assumedMinutes == 30)
        #expect(!group.overlaps(lessonStart: minutes(9, 20)), "the lesson ends as the group starts")
        #expect(group.overlaps(lessonStart: minutes(9, 21)))
        #expect(group.overlaps(lessonStart: minutes(9, 50)))
        #expect(group.overlaps(lessonStart: minutes(10, 19)))
        #expect(!group.overlaps(lessonStart: minutes(10, 20)), "the group ends as the lesson starts")
        #expect(TimetableBlockValues.overlaps(lessonStart: minutes(9, 45), block: group))
        let noLength = TimetableBlockValues(startMinute: minutes(10), lengthMinutes: 0)
        #expect(!noLength.overlaps(lessonStart: minutes(9, 50)))
    }

    @Test("A child in two groups: both clash with a lesson across them, and the lines say so")
    func childInTwoGroups() {
        let day = awayDay([
            block(nicole, minutes(9, 15), 30, children: [lucy]),
            block(devora, minutes(9, 50), 30, children: [lucy])
        ])
        let clashes = day.clashes(children: [lucy], start: minutes(9, 40))
        #expect(clashes.map(\.block.personName) == ["Miss Nicole", "Morah Devora"])
        #expect(clashes.allSatisfy { $0.studentIDs == [lucy.uppercased()] })
        #expect(day.clashes(children: [lucy], start: minutes(9, 15)).map(\.block.personName) == ["Miss Nicole"])
        #expect(AwayText.clashLine(clashes, start: minutes(9, 40), name: name) == "Lucy T is away during this lesson")
        let morning = day.away(children: [lucy], in: .morning)
        #expect(morning.count == 2)
        #expect(AwayText.untimedLine(morning, half: .morning, name: name) == "Lucy T is away part of the morning")
        #expect(day.away(children: [lucy], in: .afternoon).isEmpty)
        #expect(day.away(children: [ora]).isEmpty)
    }

    // MARK: - Free times

    @Test("A Monday shaped like the real one leaves 8:45 the only morning start, and the afternoon free")
    func realMondayFreeStarts() {
        let children = [lucy, ora]
        #expect(realMonday.freeStarts(children: children, ownStarts: []) == [minutes(8, 45)])
        #expect(realMonday.freeHalves(children: children) == [.afternoon])
        #expect(AwayText.freeWords(realMonday.freeHalves(children: children)) == "Free all afternoon")
        // Nobody of this lesson away: both halves free, and nothing to say.
        #expect(realMonday.freeHalves(children: [naomi]) == [.morning, .afternoon])
        #expect(realMonday.freeStarts(children: [naomi], ownStarts: []).isEmpty)
        #expect(AwayText.freeWords(realMonday.freeHalves(children: [naomi])) == nil)
    }

    @Test("The guide's own timed lessons block a start within 30 minutes either side")
    func ownLessonsBlockStarts() {
        let day = awayDay([block(devora, minutes(9, 15), 30, children: [lucy])])
        #expect(day.freeStarts(children: [lucy], ownStarts: []) == [minutes(8, 45), minutes(9, 45)])
        // A lesson of his at 10:00 takes 9:35 through 10:25.
        #expect(day.freeStarts(children: [lucy], ownStarts: [minutes(10)]) == [minutes(8, 45), minutes(10, 30)])
        // One exactly 30 minutes away doesn't: 9:45 stays free, and 10:15 takes 9:50 through 10:40.
        #expect(day.freeStarts(children: [lucy], ownStarts: [minutes(10, 15)]) == [
            minutes(8, 45), minutes(9, 45), minutes(10, 45)
        ])
        #expect(day.freeStarts(children: [lucy], ownStarts: [minutes(8, 45)]) == [minutes(9, 45)])
    }

    @Test("Four chips at most, the morning's first")
    func atMostFourChips() {
        let day = awayDay([
            block(devora, minutes(9), 5, children: [lucy]),
            block(devora, minutes(10), 5, children: [lucy]),
            block(nicole, minutes(13, 30), 5, children: [lucy]),
            block(nicole, minutes(14, 30), 5, children: [lucy])
        ])
        #expect(day.freeStarts(children: [lucy], ownStarts: []) == [
            minutes(9, 5), minutes(10, 5), minutes(13), minutes(13, 35)
        ])
        #expect(AwayText.freeWords(day.freeHalves(children: [lucy])) == nil)
    }

    @Test("A group that runs past noon takes the afternoon too")
    func groupAcrossNoon() {
        let day = awayDay([block(devora, minutes(11, 45), 90, children: [lucy])])
        #expect(day.freeHalves(children: [lucy]).isEmpty)
        #expect(day.clashes(children: [lucy], start: minutes(13)).count == 1)
        #expect(day.freeStarts(children: [lucy], ownStarts: []) == [minutes(8, 45), minutes(13, 15)])
    }

    // MARK: - Which groups count

    @Test("With no lane marked as the guide's, nobody counts as away")
    func noGuideLane() {
        let unmarked = TimetableLaneSnapshot(name: "Danny", kind: .person, sortOrder: 2)
        let resolved = ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: Support.monday, lanes: [unmarked, devora],
            blocks: [block(devora, minutes(9, 50), 30, children: [lucy])], calendar: Support.calendar
        ))
        #expect(AwayTimes.day(from: resolved).isEmpty)
        #expect(AwayTimes.day(from: resolved, guideLaneID: unmarked.id).blocks.count == 1)
    }

    @Test("A group cancelled for the day, a co-teacher out, and a day with no school give no away times")
    func cancelledOutAndNoSchool() {
        let group = block(devora, minutes(9, 50), 30, children: [lucy])
        let other = block(nicole, minutes(9, 15), 30, children: [ora])
        #expect(awayDay([group, other]).blocks.count == 2)
        let cancelled = TimetableChangeSnapshot(
            day: Support.monday, kind: .cancelled, blockID: group.id, values: group.values
        )
        #expect(awayDay([group, other], changes: [cancelled]).blocks.map(\.personName) == ["Miss Nicole"])
        let out = TimetableChangeSnapshot(day: Support.monday, kind: .out, laneID: nicole.id)
        #expect(awayDay([group, other], changes: [out]).blocks.map(\.personName) == ["Morah Devora"])
        #expect(awayDay([group, other], isSchoolDay: false).isEmpty)
    }

    @Test("Only This Day's values are the ones that count")
    func changedForTheDay() {
        let group = block(devora, minutes(9, 50), 30, children: [lucy])
        var moved = group.values
        moved.startMinute = minutes(13)
        moved.studentIDs = [ora]
        let change = TimetableChangeSnapshot(day: Support.monday, kind: .changed, blockID: group.id, values: moved)
        let day = awayDay([group], changes: [change])
        #expect(day.blocks.map(\.startMinute) == [minutes(13)])
        #expect(day.away(children: [lucy]).isEmpty)
        #expect(day.away(children: [ora], in: .afternoon).count == 1)
    }

    @Test("A turn in the adolescent room, a room's block and the guide's own lane give no away times")
    func turnsRoomsAndTheGuide() {
        let day = awayDay([
            block(room, minutes(10), 45, "Devora's turn", children: [lucy], teacher: devora),
            block(ourClass, minutes(9), 60, "Morning work", children: [ora]),
            block(guide, minutes(11), 30, "Mine", children: [leora]),
            block(devora, minutes(13), 30, "No children", children: [])
        ])
        #expect(day.isEmpty)
    }

    // MARK: - The words

    @Test("The card's line for a set time: leaves, is with, two children, and more")
    func timedLines() {
        let day = realMonday
        let leaves = day.clashes(children: [lucy], start: minutes(9, 45))
        #expect(leaves.map(\.block.personName) == ["Morah Devora"])
        #expect(AwayText.clashLine(leaves, start: minutes(9, 45), name: name)
            == "Lucy T leaves at 9:50 for Morah Devora")
        let already = day.clashes(children: [lucy], start: minutes(10))
        #expect(AwayText.clashLine(already, start: minutes(10), name: name)
            == "Lucy T is with Morah Devora until 10:20")
        let two = day.clashes(children: [lucy, ora], start: minutes(9, 15))
        #expect(AwayText.clashLine(two, start: minutes(9, 15), name: name)
            == "Lucy T and Ora P are with Miss Nicole until 9:45")
        let twoLeave = day.clashes(children: [lucy, ora], start: minutes(9))
        #expect(AwayText.clashLine(twoLeave, start: minutes(9), name: name)
            == "Lucy T and Ora P leave at 9:15 for Miss Nicole")
        let threeChildren = awayDay([block(nicole, minutes(9, 15), 30, children: [lucy, ora, leora])])
            .clashes(children: [lucy, ora, leora], start: minutes(9, 15))
        #expect(AwayText.clashLine(threeChildren, start: minutes(9, 15), name: name)
            == "3 children are away during this lesson")
        let twoGroups = day.clashes(children: [lucy, ora], start: minutes(9, 30))
        #expect(twoGroups.count == 2)
        #expect(AwayText.clashLine(twoGroups, start: minutes(9, 30), name: name)
            == "2 children are away during this lesson")
        #expect(AwayText.clashLine([], start: minutes(9), name: name) == nil)
        #expect(AwayText.clashLine(leaves, start: minutes(9, 45)) { _ in nil }
            == "A child leaves at 9:50 for Morah Devora")
    }

    @Test("The quiet line for a lesson with no time")
    func untimedLines() {
        let one = awayDay([block(devora, minutes(9, 50), 30, children: [lucy])])
        #expect(AwayText.untimedLine(one.away(children: [lucy], in: .morning), half: .morning, name: name)
            == "Lucy T is away 9:50–10:20")
        let sisters = awayDay([block(devora, minutes(9, 50), 30, children: [leora, naomi])])
        #expect(AwayText.untimedLine(
            sisters.away(children: [leora, naomi], in: .morning), half: .morning, name: name
        ) == "Leora F and Naomi F are away 9:50–10:20")
        #expect(AwayText.untimedLine(
            realMonday.away(children: [lucy, ora], in: .morning), half: .morning, name: name
        ) == "2 children are away part of the morning")
        #expect(AwayText.untimedLine([], half: .morning, name: name) == nil)
    }

    @Test("The picker's Away rows, and the fixed words")
    func pickerWords() {
        let rows = realMonday.away(children: [lucy, ora]).map { AwayText.awayRow($0, name: name) }
        #expect(rows == [
            "9:15–9:45 · Lucy T, Ora P · Miss Nicole",
            "9:50–10:20 · Lucy T · Morah Devora",
            "10:40–11:10 · Ora P · Morah Devora"
        ])
        #expect(AwayText.freeWords([.morning]) == "Free all morning")
        #expect(AwayText.badgeCount(2) == "2 with a child away")
        #expect(AwayText.chipSpoken == "a child is with another teacher then")
        #expect(AwayText.legend == "A child is with another teacher")
    }

    @Test("MCP's sentences: a set time that overlaps, and a lesson with no time")
    func mcpLines() {
        let timed = realMonday.clashes(children: [lucy], start: minutes(10))
        #expect(AwayText.scheduledLines(timed, lessonMinute: minutes(10), name: name)
            == ["Lucy T is with Morah Devora 9:50–10:20."])
        let untimed = realMonday.away(children: [lucy, ora], in: .morning)
        #expect(AwayText.scheduledLines(untimed, lessonMinute: nil, name: name) == [
            "Lucy T and Ora P are away 9:15–9:45 that morning.",
            "Lucy T is away 9:50–10:20 that morning.",
            "Ora P is away 10:40–11:10 that morning."
        ])
    }

    // MARK: - From the store

    @Test("AwayTimes.days covers a range from the store, keyed by day, with cancels and no-school days")
    func daysFromTheStore() throws {
        let context = try Support.context()
        TimetableService.makeStarterLanes(in: context)
        let person = TimetableService.addPerson(named: "Morah Devora", in: context)
        let blocks = TimetableService.addBlock(
            TimetableBlockValues(startMinute: minutes(9, 50), lengthMinutes: 30, title: "Chumash", studentIDs: [lucy]),
            to: person, on: [.monday, .wednesday], in: context
        )
        let monday = try #require(blocks.first { $0.weekday == .monday })
        TimetableService.cancel(monday, on: Support.nextMonday, in: context)
        let dayOff = CDNonSchoolDay(context: context)
        dayOff.date = Support.wednesday
        #expect(context.safeSave())

        let days = AwayTimes.days(from: Support.monday, through: Support.nextMonday, in: context)
        #expect(days.count == 8)
        #expect(days[Support.monday]?.away(children: [lucy]).map(\.block.title) == ["Chumash"])
        #expect(days[Support.tuesday]?.isEmpty == true)
        #expect(days[Support.wednesday]?.isEmpty == true, "no school that Wednesday")
        #expect(days[Support.nextMonday]?.isEmpty == true, "cancelled that Monday")
        #expect(AwayTimes.days(from: Support.tuesday, through: Support.monday, in: context).isEmpty)
    }
}
