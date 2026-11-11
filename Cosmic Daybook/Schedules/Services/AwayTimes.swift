// AwayTimes.swift
// Which children are away with a co-teacher, and when, on a day: the groups
// in people's lanes other than the guide's, as the Schedules page resolves
// the day (Only This Day changes, cancels, Out Today and no-school days all
// counted). The planner's time picker, its cards, the lesson's sheet and MCP
// read it (plan "Co-teacher times when scheduling", decisions 2, 3 and 5).
// The values and rules are plain; only `AwayTimes.days` reads the store.

import CoreData
import Foundation

/// One co-teacher's group on a day, with the children it takes.
nonisolated struct AwayBlock: Sendable, Equatable, Identifiable {
    let blockID: UUID
    /// Whose lane it is ("Morah Devora").
    let personName: String
    let title: String
    /// Minutes after midnight.
    let startMinute: Int
    let endMinute: Int
    /// Upper-cased student IDs.
    let studentIDs: [String]

    var id: UUID { blockID }

    /// The half the group starts in, as the Schedules page files it.
    var half: ScheduleDayHalf { ScheduleDayHalf(minute: startMinute) }

    /// Every half the group runs in: one that goes on past noon is in both.
    var halves: Set<ScheduleDayHalf> {
        var halves: Set<ScheduleDayHalf> = [half]
        if endMinute > ScheduleDayHalf.noon { halves.insert(.afternoon) }
        return halves
    }

    var values: TimetableBlockValues {
        TimetableBlockValues(startMinute: startMinute, lengthMinutes: endMinute - startMinute, title: title)
    }

    /// Whether a lesson starting at `lessonStart` overlaps the group (decision 2).
    func overlaps(lessonStart: Int) -> Bool {
        values.overlaps(lessonStart: lessonStart)
    }
}

/// A group, and which of a lesson's children it takes.
nonisolated struct AwayClash: Sendable, Equatable {
    let block: AwayBlock
    /// Upper-cased, in the lesson's order.
    let studentIDs: [String]
}

/// One day's groups, in time order, with the rules the picker, the cards and
/// MCP use.
nonisolated struct AwayDay: Sendable, Equatable {
    /// In time order.
    let blocks: [AwayBlock]

    static let empty = AwayDay(blocks: [])

    init(blocks: [AwayBlock]) {
        self.blocks = blocks.sorted { lhs, rhs in
            if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
            if lhs.endMinute != rhs.endMinute { return lhs.endMinute < rhs.endMinute }
            return lhs.blockID.uuidString < rhs.blockID.uuidString
        }
    }

    var isEmpty: Bool { blocks.isEmpty }

    /// Student IDs as the rules compare them.
    static func keys(_ children: some Sequence<String>) -> [String] {
        var seen = Set<String>()
        return children.map { $0.uppercased() }.filter { seen.insert($0).inserted }
    }

    /// Student UUIDs as the rules compare them.
    static func keys(_ children: some Sequence<UUID>) -> [String] {
        keys(children.map(\.uuidString))
    }

    /// The groups that take any of `children`, each with those children.
    func away(children: [String]) -> [AwayClash] {
        let keys = Self.keys(children)
        guard !keys.isEmpty else { return [] }
        return blocks.compactMap { block in
            let taken = Set(block.studentIDs)
            let ids = keys.filter(taken.contains)
            return ids.isEmpty ? nil : AwayClash(block: block, studentIDs: ids)
        }
    }

    /// The groups starting in `half` that take any of `children`: what an
    /// untimed lesson in that half is told about.
    func away(children: [String], in half: ScheduleDayHalf) -> [AwayClash] {
        away(children: children).filter { $0.block.half == half }
    }

    /// The groups a lesson starting at `start` overlaps that take any of
    /// `children`, in time order.
    func clashes(children: [String], start: Int) -> [AwayClash] {
        away(children: children).filter { $0.block.overlaps(lessonStart: start) }
    }

    /// The halves in which no group takes any of `children` (a group that
    /// runs past noon takes both).
    func freeHalves(children: [String]) -> [ScheduleDayHalf] {
        let taken = Set(away(children: children).flatMap(\.block.halves))
        return ScheduleDayHalf.allCases.filter { !taken.contains($0) }
    }

    /// The suggested starts for a lesson with `children` (decision 5): every 5
    /// minutes in the quick-time hours, a start is free when none of the
    /// children is in a group during its 30 minutes and none of the guide's
    /// other timed lessons (`ownStarts`) starts within 30 minutes either side.
    /// Free starts in a row form a stretch, and each stretch gives its first
    /// start: morning first, four at most. A half with no group for these
    /// children gives none (it reads "Free all morning" instead).
    func freeStarts(children: [String], ownStarts: [Int]) -> [Int] {
        let away = away(children: children)
        let busyHalves = Set(away.flatMap(\.block.halves))
        var starts: [Int] = []
        for half in ScheduleDayHalf.allCases where busyHalves.contains(half) {
            var inStretch = false
            for start in Self.candidateStarts(in: half) {
                let free = !away.contains { $0.block.overlaps(lessonStart: start) }
                    && !ownStarts.contains { abs($0 - start) < LessonLength.assumedMinutes }
                if free, !inStretch { starts.append(start) }
                inStretch = free
            }
        }
        return Array(starts.prefix(Self.maxSuggestions))
    }

    /// At most this many "Everyone's free" chips.
    static let maxSuggestions = 4

    /// Every 5 minutes from the half's first quick time through its last.
    static func candidateStarts(in half: ScheduleDayHalf) -> [Int] {
        let times = LessonTimeChoices.quickTimes(for: half == .morning ? .morning : .afternoon)
        guard let first = times.first, let last = times.last else { return [] }
        return Array(stride(from: first, through: last, by: 5))
    }
}

/// Builds the days' away times from the timetable.
enum AwayTimes {

    /// The groups in `day` that take children: a person lane's own blocks, in
    /// every lane but the guide's (decision 3). A turn in a room also shows in
    /// its teacher's lane and is left out, as are room blocks. The day as
    /// resolved already has cancels, changes, Out Today and no school in it.
    /// `guideLaneID` nil means the day's `isGuide` person lane; with no guide
    /// lane at all nobody counts as away, as the resolver then warns about
    /// nobody (his own lane can't be told apart).
    nonisolated static func day(from day: ScheduleDay, guideLaneID: UUID? = nil) -> AwayDay {
        guard day.isSchoolDay,
              let guide = guideLaneID ?? day.lanes.first(where: { $0.lane.isGuide && $0.lane.kind == .person })?.lane.id
        else { return .empty }
        var blocks: [AwayBlock] = []
        for lane in day.lanes where lane.lane.kind == .person && lane.lane.id != guide && !lane.isOut {
            for item in lane.items {
                guard case .block(let block) = item.kind, block.laneID == lane.lane.id,
                      block.values.lengthMinutes > 0 else { continue }
                let children = AwayDay.keys(block.values.studentIDs)
                guard !children.isEmpty else { continue }
                blocks.append(AwayBlock(
                    blockID: block.id, personName: personName(lane.lane), title: block.values.title.trimmed(),
                    startMinute: block.values.startMinute, endMinute: block.values.endMinute,
                    studentIDs: children
                ))
            }
        }
        return AwayDay(blocks: blocks)
    }

    /// The away times of every day from `start` through `end`, keyed by start
    /// of day: one timetable fetch and one school-calendar fetch for the
    /// whole range, then the resolver per day with no lessons.
    static func days(
        from start: Date,
        through end: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [Date: AwayDay] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [:] }
        var dayList: [Date] = []
        var cursor = first
        // A planner's window is weeks, not years: stop well short of a runaway range.
        while cursor <= last, dayList.count < maxDays {
            dayList.append(cursor)
            cursor = TimetableService.dayAfter(cursor, calendar: calendar)
        }
        let timetable = TimetableService.timetable(from: first, through: last, in: context, calendar: calendar)
        let persons = timetable.lanes.filter { $0.kind == .person }
        guard persons.contains(where: \.isGuide), persons.contains(where: { !$0.isGuide }) else {
            return Dictionary(uniqueKeysWithValues: dayList.map { ($0, AwayDay.empty) })
        }
        let nonSchool = SchoolDayChecker.nonSchoolDaySet(
            in: first..<TimetableService.dayAfter(last, calendar: calendar), using: context, calendar: calendar
        )
        return Dictionary(uniqueKeysWithValues: dayList.map { day in
            let resolved = ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
                day: day, lanes: timetable.lanes, blocks: timetable.blocks, changes: timetable.changes,
                isSchoolDay: !nonSchool.contains(day), calendar: calendar
            ))
            return (day, Self.day(from: resolved))
        })
    }

    /// The longest range `days` works out.
    static let maxDays = 400

    nonisolated private static func personName(_ lane: TimetableLaneSnapshot) -> String {
        let name = lane.name.trimmed()
        return name.isEmpty ? "another teacher" : name
    }
}
