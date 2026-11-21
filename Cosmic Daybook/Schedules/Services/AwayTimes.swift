// AwayTimes.swift
// The day's busy picture for the guide's lessons: which children are away,
// and when (a co-teacher's group, leaving early, absent), the guide's own
// turns in a room, and whether he is out, worked out from the day as the
// Schedules page resolves it (Only This Day changes, cancels, Out Today and
// no-school days all counted). The planner's time picker, its cards and day
// badge, the lesson's sheet and MCP read it (plan "Co-teacher times when
// scheduling", decisions 2, 3 and 5; plan "Domain logic fixes", R16).
// The values and rules are plain; only `AwayTimes.days` reads the store.

import CoreData
import Foundation

/// Why a child is away for a stretch of the day.
nonisolated enum AwayReason: Sendable, Equatable {
    /// In a co-teacher's group.
    case group
    /// Going home early, from `AwayBlock.startMinute` on.
    case leavingEarly
    /// Absent all day.
    case absent
}

/// One stretch of the day some children are away: a co-teacher's group, or
/// children leaving early or absent.
nonisolated struct AwayBlock: Sendable, Equatable, Identifiable {
    let blockID: UUID
    /// Whose lane it is ("Morah Devora"); empty for leaving early and absent.
    let personName: String
    let title: String
    /// Minutes after midnight.
    let startMinute: Int
    let endMinute: Int
    /// Upper-cased student IDs.
    let studentIDs: [String]
    var reason: AwayReason = .group

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

    /// The end of the day, for a child leaving early or absent.
    static let endOfDay = 24 * 60

    /// A child away from class, as a stretch of the day: from the time she
    /// leaves, or the whole day.
    init(_ away: ScheduleChildAway, day: Date) {
        let start = away.fromMinute ?? 0
        self.init(
            blockID: Self.childAwayID(away.studentID, day: day), personName: "", title: "",
            startMinute: start, endMinute: Self.endOfDay, studentIDs: [away.studentID],
            reason: away.fromMinute == nil ? .absent : .leavingEarly
        )
    }

    init(
        blockID: UUID, personName: String, title: String, startMinute: Int, endMinute: Int, studentIDs: [String],
        reason: AwayReason = .group
    ) {
        self.blockID = blockID
        self.personName = personName
        self.title = title
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.studentIDs = studentIDs
        self.reason = reason
    }

    /// A steady id for a child's time away on a day, so the list keeps its
    /// order between reloads: her ID's bytes with the day's.
    private static func childAwayID(_ studentID: String, day: Date) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        if let id = UUID(uuidString: studentID) { bytes = withUnsafeBytes(of: id.uuid) { Array($0) } }
        let seconds = UInt64(max(0, day.timeIntervalSinceReferenceDate))
        for index in 0..<8 { bytes[8 + index] ^= UInt8((seconds >> (8 * UInt64(index))) & 0xFF) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// One of the guide's own turns in a room: he can't give another lesson then.
nonisolated struct AwayTurn: Sendable, Equatable, Identifiable {
    let blockID: UUID
    /// The room ("Adolescent room").
    let roomName: String
    /// The room holds his adolescents' lessons (`ScheduleDayResolver.turnRoomIDs`),
    /// so a lesson for adolescents only is given in the turn, not kept from it.
    let holdsAdolescentLessons: Bool
    let startMinute: Int
    let endMinute: Int

    var id: UUID { blockID }

    var values: TimetableBlockValues {
        TimetableBlockValues(startMinute: startMinute, lengthMinutes: endMinute - startMinute)
    }

    var halves: Set<ScheduleDayHalf> {
        var halves: Set<ScheduleDayHalf> = [ScheduleDayHalf(minute: startMinute)]
        if endMinute > ScheduleDayHalf.noon { halves.insert(.afternoon) }
        return halves
    }

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

/// One day's busy picture, with the rules the picker, the cards, the day
/// badge and MCP use: the stretches children are away (`blocks`, in time
/// order), the guide's turns, and whether he is out.
nonisolated struct AwayDay: Sendable, Equatable {
    /// In time order.
    let blocks: [AwayBlock]
    /// The guide's turns in a room, in time order.
    var turns: [AwayTurn] = []
    /// The guide is out (Out Today): none of his lessons can be given.
    var guideIsOut = false
    /// The adolescents among the children, upper-cased: a lesson for them
    /// alone goes in his turn in the adolescent room.
    var adolescentIDs: Set<String> = []

    static let empty = AwayDay(blocks: [])

    init(
        blocks: [AwayBlock], turns: [AwayTurn] = [], guideIsOut: Bool = false, adolescentIDs: Set<String> = []
    ) {
        self.blocks = blocks.sorted { lhs, rhs in
            if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
            if lhs.endMinute != rhs.endMinute { return lhs.endMinute < rhs.endMinute }
            return lhs.blockID.uuidString < rhs.blockID.uuidString
        }
        self.turns = turns.sorted { lhs, rhs in
            if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
            return lhs.blockID.uuidString < rhs.blockID.uuidString
        }
        self.guideIsOut = guideIsOut
        self.adolescentIDs = Set(adolescentIDs.map { $0.uppercased() })
    }

    /// Nothing on the day keeps any lesson from any time.
    var isEmpty: Bool { blocks.isEmpty && turns.isEmpty && !guideIsOut }

    /// Whether anything on the day touches a lesson with `children`: one of
    /// them is away, he has a turn that keeps it, or he is out.
    func touches(children: [String]) -> Bool {
        guideIsOut || !away(children: children).isEmpty || !busyTurns(children: children).isEmpty
    }

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
    /// untimed lesson in that half is told about. A child leaving early in
    /// the morning, or absent, is away in the afternoon too.
    func away(children: [String], in half: ScheduleDayHalf) -> [AwayClash] {
        away(children: children).filter { clash in
            clash.block.reason == .group ? clash.block.half == half : clash.block.halves.contains(half)
        }
    }

    /// The groups a lesson starting at `start` overlaps that take any of
    /// `children`, in time order.
    func clashes(children: [String], start: Int) -> [AwayClash] {
        away(children: children).filter { $0.block.overlaps(lessonStart: start) }
    }

    /// The guide's turns that keep a lesson with `children` from their time:
    /// all of them, except that a lesson for adolescents only belongs in his
    /// turn in the adolescent room.
    func busyTurns(children: [String]) -> [AwayTurn] {
        let keys = Self.keys(children)
        let adolescentsOnly = !keys.isEmpty && keys.allSatisfy(adolescentIDs.contains)
        return turns.filter { !(adolescentsOnly && $0.holdsAdolescentLessons) }
    }

    /// The guide's turn a lesson with `children` starting at `start` overlaps, if any.
    func turnClash(children: [String], start: Int) -> AwayTurn? {
        busyTurns(children: children).first { $0.overlaps(lessonStart: start) }
    }

    /// The halves in which nothing keeps a lesson with `children`: none of
    /// them is away and the guide has no turn (a stretch that runs past noon
    /// takes both). None when he is out.
    func freeHalves(children: [String]) -> [ScheduleDayHalf] {
        guard !guideIsOut else { return [] }
        let taken = Set(away(children: children).flatMap(\.block.halves))
            .union(busyTurns(children: children).flatMap(\.halves))
        return ScheduleDayHalf.allCases.filter { !taken.contains($0) }
    }

    /// The suggested starts for a lesson with `children` (decision 5): every 5
    /// minutes in the quick-time hours, a start is free when none of the
    /// children is away during its 30 minutes, it doesn't overlap one of the
    /// guide's turns, and none of his other timed lessons (`ownStarts`)
    /// starts within 30 minutes either side. Free starts in a row form a
    /// stretch, and each stretch gives its first start: morning first, four
    /// at most. A half with nothing busy for these children gives none (it
    /// reads "Free all morning" instead), and a day he is out gives none.
    func freeStarts(children: [String], ownStarts: [Int]) -> [Int] {
        guard !guideIsOut else { return [] }
        let away = away(children: children)
        let turns = busyTurns(children: children)
        let busyHalves = Set(away.flatMap(\.block.halves)).union(turns.flatMap(\.halves))
        var starts: [Int] = []
        for half in ScheduleDayHalf.allCases where busyHalves.contains(half) {
            var inStretch = false
            for start in Self.candidateStarts(in: half) {
                let free = !away.contains { $0.block.overlaps(lessonStart: start) }
                    && !turns.contains { $0.overlaps(lessonStart: start) }
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

    /// The day's busy picture from `day` as resolved, which already has
    /// cancels, changes, Out Today and no school in it:
    /// - the children away from class (`ScheduleDay.childrenAway`);
    /// - the groups that take children: a person lane's own blocks, in every
    ///   lane but the guide's (decision 3). A turn in a room also shows in its
    ///   teacher's lane and is left out, as are room blocks;
    /// - the guide's own turns in a room, and whether he is out.
    ///
    /// `guideLaneID` nil means the day's `isGuide` person lane; with no guide
    /// lane at all no group counts and he has no turns, as the resolver then
    /// warns about nobody (his own lane can't be told apart). `adolescentIDs`
    /// are the adolescents, whose lessons for them alone go in his turn.
    nonisolated static func day(
        from day: ScheduleDay, guideLaneID: UUID? = nil, adolescentIDs: Set<String> = []
    ) -> AwayDay {
        guard day.isSchoolDay else { return .empty }
        var blocks = day.childrenAway.map { AwayBlock($0, day: day.day) }
        guard let guide = guideLaneID
            ?? day.lanes.first(where: { $0.lane.isGuide && $0.lane.kind == .person })?.lane.id
        else { return AwayDay(blocks: blocks, adolescentIDs: adolescentIDs) }
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
        let guideLane = day.lane(guide)
        let turnRooms = ScheduleDayResolver.turnRoomIDs(in: day.lanes.map(\.lane))
        let turns: [AwayTurn] = (guideLane?.items ?? []).compactMap { item in
            guard case .turn(let block) = item.kind, block.values.lengthMinutes > 0 else { return nil }
            return AwayTurn(
                blockID: block.id, roomName: day.lane(block.laneID)?.lane.name.trimmed() ?? "",
                holdsAdolescentLessons: turnRooms.contains(block.laneID),
                startMinute: block.values.startMinute, endMinute: block.values.endMinute
            )
        }
        return AwayDay(
            blocks: blocks, turns: turns, guideIsOut: guideLane?.isOut ?? false, adolescentIDs: adolescentIDs
        )
    }

    /// The busy picture of every day from `start` through `end`, keyed by
    /// start of day: one timetable fetch, one school-calendar fetch and one
    /// attendance fetch for the whole range, then the resolver per day with
    /// no lessons.
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
        let childrenAway = ScheduleChildrenAway.days(from: first, through: last, in: context, calendar: calendar)
        let hasGuide = timetable.lanes.contains { $0.kind == .person && $0.isGuide }
        guard hasGuide || !childrenAway.isEmpty else {
            return Dictionary(uniqueKeysWithValues: dayList.map { ($0, AwayDay.empty) })
        }
        let nonSchool = SchoolDayChecker.nonSchoolDaySet(
            in: first..<TimetableService.dayAfter(last, calendar: calendar), using: context, calendar: calendar
        )
        let adolescentIDs: Set<String> = hasGuide
            ? Set(ScheduleLessonPlan.studentLevels(in: context).filter { $0.value == .adolescent }.keys)
            : []
        return Dictionary(uniqueKeysWithValues: dayList.map { day in
            let resolved = ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
                day: day, lanes: timetable.lanes, blocks: timetable.blocks, changes: timetable.changes,
                isSchoolDay: !nonSchool.contains(day), childrenAway: childrenAway[day] ?? [], calendar: calendar
            ))
            return (day, Self.day(from: resolved, adolescentIDs: adolescentIDs))
        })
    }

    /// The longest range `days` works out.
    static let maxDays = 400

    nonisolated private static func personName(_ lane: TimetableLaneSnapshot) -> String {
        let name = lane.name.trimmed()
        return name.isEmpty ? "another teacher" : name
    }
}
