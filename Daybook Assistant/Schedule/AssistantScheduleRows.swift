import Foundation

/// What the Schedule tab says, worked out from a resolved day as plain
/// strings: the rows in time order, the Now card, and the changed line.
///
/// Only lane names, block titles and notes as the guide typed them, the
/// children's short names, and fixed words go into these strings. A lesson's
/// name never reaches here: the Assistant's lessons come from bookings, and
/// nothing below reads a lesson's title even when one is set.
enum AssistantScheduleRows {

    /// The guide's name when neither he nor Apple gives one.
    static let guideFallbackName = "Your guide"

    /// The names the rows are worded with.
    struct Names: Equatable {
        /// The guide's name as her screens show it, or "Your guide".
        var guideName: String
        /// Children's short names by upper-cased student ID.
        var children: [String: String]

        /// The children's short names, in the order given, each once; a child
        /// she can't see (one who left) is left out.
        func children(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.compactMap { id in
                let key = id.uppercased()
                guard seen.insert(key).inserted else { return nil }
                return children[key]
            }
        }
    }

    /// A lane in the filter menu.
    struct LaneOption: Identifiable, Equatable {
        let id: UUID
        let name: String
        let colorRaw: String
        /// Its place among the lanes, for a color when the guide chose none.
        let index: Int
    }

    /// What a row is.
    enum RowKind: Equatable {
        /// A lane's own block.
        case block
        /// A room's block shown in the person's lane who teaches it.
        case turn
        /// One of the guide's planned lessons: children only.
        case withGuide
    }

    /// One row of the day.
    struct Row: Identifiable, Equatable {
        let id: String
        let kind: RowKind
        let laneID: UUID
        /// The lane's name, as its tag.
        let laneName: String
        let laneColorRaw: String
        let laneIndex: Int
        /// "9:00–9:45", "10:30", or "Morning".
        let time: String
        /// The block's title, "In the adolescent room", or "With Danny".
        let title: String
        /// Who teaches it ("Danny's turn"), or that they're out.
        let teacher: String?
        /// The block's note, as typed.
        let note: String?
        /// The children's short names.
        let children: [String]
        /// "Changed" or "This day only", when the guide changed the day.
        let marker: String?
        /// Its teacher is out: the row reads as off.
        let isOut: Bool
    }

    // MARK: - Rows

    /// The day's rows in time order. With every lane (`lane` nil) a turn
    /// shows once, as the room's block naming who teaches it; with one
    /// person's lane, it shows as that person's turn.
    static func rows(for day: ScheduleDay, lane filter: UUID?, names: Names) -> [Row] {
        guard day.isSchoolDay else { return [] }
        var rows: [Placed] = []
        for (laneIndex, lane) in day.lanes.enumerated() {
            if let filter, lane.id != filter { continue }
            let place = LanePlace(
                lane: lane, index: laneIndex, name: name(of: lane.lane, guideName: names.guideName),
                day: day, names: names, everyLane: filter == nil
            )
            for item in lane.items {
                for row in rowsFor(item, in: place) {
                    rows.append(Placed(
                        minute: item.startMinute, rank: item.kind.rowRank, laneIndex: laneIndex,
                        order: rows.count, row: row
                    ))
                }
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.laneIndex != rhs.laneIndex { return lhs.laneIndex < rhs.laneIndex }
            return lhs.order < rhs.order
        }.map(\.row)
    }

    /// A row with where it sorts: by time, then blocks before lessons, then
    /// by lane, then in the order made (the guide's order in a half).
    private struct Placed {
        let minute: Int
        let rank: Int
        let laneIndex: Int
        let order: Int
        let row: Row
    }

    /// The lane a row is made in, and what its words need.
    private struct LanePlace {
        let lane: ScheduleDay.Lane
        let index: Int
        let name: String
        let day: ScheduleDay
        let names: Names
        /// Every lane shows, so a turn shows only as the room's block.
        let everyLane: Bool
    }

    private static func rowsFor(_ item: ScheduleDay.Item, in place: LanePlace) -> [Row] {
        let (lane, day, names, laneName) = (place.lane, place.day, place.names, place.name)
        func row(id: String, kind: RowKind, time: String, title: String, teacher: String? = nil,
                 note: String? = nil, children: [String], marker: String? = nil, isOut: Bool = false) -> Row {
            Row(id: "\(lane.id.uuidString)-\(id)", kind: kind, laneID: lane.id, laneName: laneName,
                laneColorRaw: lane.lane.colorRaw, laneIndex: place.index, time: time, title: title,
                teacher: teacher, note: note, children: children, marker: marker, isOut: isOut)
        }
        switch item.kind {
        case .block(let block):
            let title = block.values.title.trimmed()
            return [row(
                id: item.id, kind: .block, time: TimetableDay.rangeText(block.values),
                title: title.isEmpty ? laneName : title,
                teacher: teacherLine(block, day: day, names: names), note: noteText(block),
                children: names.children(block.studentIDs), marker: marker(block), isOut: block.teacherIsOut
            )]
        case .turn(let block):
            // With every lane showing, the room's own row already says whose turn it is.
            guard !place.everyLane else { return [] }
            let room = day.lane(block.laneID).map { roomPhrase($0.lane.name) } ?? "another room"
            let title = block.values.title.trimmed()
            return [row(
                id: item.id, kind: .turn, time: TimetableDay.rangeText(block.values),
                title: "In \(room)" + (title.isEmpty ? "" : " · \(title)"), note: noteText(block),
                children: names.children(block.studentIDs), marker: marker(block)
            )]
        case .lesson(let lesson):
            let minute = lesson.snapshot.minute ?? lesson.snapshot.half.listMinute
            return [row(
                id: item.id, kind: .withGuide, time: TimetableDay.clockText(minute),
                title: "With \(names.guideName)", children: names.children(lesson.snapshot.studentIDs)
            )]
        case .halfList(let half, let lessons):
            return lessons.map { lesson in
                row(
                    id: "lesson-\(lesson.id.uuidString)", kind: .withGuide, time: halfText(half),
                    title: "With \(names.guideName)", children: names.children(lesson.snapshot.studentIDs)
                )
            }
        }
    }

    /// "Danny's turn", "Mr. Cohen's turn", or "Morah Devora is out".
    private static func teacherLine(_ block: ScheduleDay.Block, day: ScheduleDay, names: Names) -> String? {
        let teacher: String
        if let laneID = block.teacherLaneID, let lane = day.lane(laneID) {
            teacher = name(of: lane.lane, guideName: names.guideName)
        } else {
            teacher = block.values.teacherName.trimmed()
        }
        guard !teacher.isEmpty else { return nil }
        return block.teacherIsOut ? "\(teacher) is out" : "\(possessive(teacher)) turn"
    }

    private static func noteText(_ block: ScheduleDay.Block) -> String? {
        let note = block.values.note.trimmed()
        return note.isEmpty ? nil : note
    }

    private static func marker(_ block: ScheduleDay.Block) -> String? {
        if block.isOneOff { return "This day only" }
        if block.isChanged { return "Changed" }
        return nil
    }

    static func halfText(_ half: ScheduleDayHalf) -> String {
        switch half {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        }
    }

    // MARK: - The changed line

    /// "1 change today", "2 changes today", or "1 change this day" on
    /// another day; nil when the day is as the timetable has it.
    static func changedLine(for day: ScheduleDay, isToday: Bool) -> String? {
        guard day.isSchoolDay, day.changeCount > 0 else { return nil }
        let count = day.changeCount == 1 ? "1 change" : "\(day.changeCount) changes"
        return count + (isToday ? " today" : " this day")
    }

    /// "Morah Devora is out.", for each person out that day.
    static func outLines(for day: ScheduleDay, names: Names) -> [String] {
        guard day.isSchoolDay else { return [] }
        return day.lanes.filter(\.isOut).map { "\(name(of: $0.lane, guideName: names.guideName)) is out." }
    }

    // MARK: - Now

    /// The Now card: before the day's first block, after its last, or who
    /// is where.
    enum NowCard: Equatable {
        case beforeSchool
        case afterSchool
        case lines([NowLine])
    }

    struct NowLine: Identifiable, Equatable {
        let id: UUID
        let text: String
        let laneColorRaw: String
        let laneIndex: Int
    }

    /// Who is where at `minute`: each person (out, in a room on a turn, at
    /// one of their own blocks, or, for the guide, in our room), then each
    /// room with a block under way. Nil when the day has no blocks at all.
    static func nowCard(for day: ScheduleDay, minute: Int, names: Names) -> NowCard? {
        let blocks = day.lanes.flatMap(\.items).compactMap(\.block)
        guard day.isSchoolDay, let first = blocks.map(\.values.startMinute).min(),
              let last = blocks.map(\.values.endMinute).max() else { return nil }
        if minute < first { return .beforeSchool }
        if minute >= last { return .afterSchool }
        let entries = day.now(at: minute)
        let homeRoom = day.lanes.first { $0.lane.kind == .room }
        var people: [NowLine] = []
        var rooms: [NowLine] = []
        for (index, entry) in entries.enumerated() {
            let lane = entry.lane
            let laneName = name(of: lane, guideName: names.guideName)
            func line(_ text: String) -> NowLine {
                NowLine(id: lane.id, text: text, laneColorRaw: lane.colorRaw, laneIndex: index)
            }
            switch lane.kind {
            case .person:
                people.append(line(personNow(entry, name: laneName, day: day, homeRoom: homeRoom)))
            case .room:
                guard let block = entry.block else { continue }
                let title = block.values.title.trimmed()
                rooms.append(line("\(laneName): \(title.isEmpty ? "busy" : title)\(until(entry))."))
            }
        }
        return .lines(people + rooms)
    }

    /// Where one person is: out, in a room on a turn, at one of their own
    /// blocks, or, for the guide with nothing else, in our room.
    private static func personNow(
        _ entry: ScheduleDay.NowEntry, name: String, day: ScheduleDay, homeRoom: ScheduleDay.Lane?
    ) -> String {
        if entry.isOut { return "\(name) is out today." }
        if let roomID = entry.roomLaneID, let room = day.lane(roomID) {
            return "\(name) is in \(roomPhrase(room.lane.name))\(until(entry))."
        }
        if let block = entry.block {
            let title = block.values.title.trimmed()
            return title.isEmpty ? "\(name) is busy\(until(entry))." : "\(name): \(title)\(until(entry))."
        }
        if entry.lane.isGuide, let homeRoom { return "\(name) is in \(roomPhrase(homeRoom.lane.name))." }
        return "Nothing on \(possessive(name)) schedule now."
    }

    /// " until 10:30", or nothing.
    private static func until(_ entry: ScheduleDay.NowEntry) -> String {
        entry.until.map { " until \(TimetableDay.clockText($0))" } ?? ""
    }

    // MARK: - Words

    /// A lane's name: the guide's own lane reads the guide's name.
    static func name(of lane: TimetableLaneSnapshot, guideName: String) -> String {
        if lane.isGuide { return guideName }
        let name = lane.name.trimmed()
        return name.isEmpty ? (lane.kind == .room ? "A room" : "Someone") : name
    }

    /// "our class", "the adolescent room": a room's name as it reads after
    /// "in". A name that starts with "our", "the" or "my" keeps it; otherwise
    /// it takes "the", and its first word drops its capital unless it's
    /// all capitals or a number follows ("Room 12" stays "the Room 12").
    static func roomPhrase(_ name: String) -> String {
        let trimmed = name.trimmed()
        guard let firstWord = trimmed.split(separator: " ").first else { return "the room" }
        let lowered = firstWord.lowercased()
        if ["our", "the", "my"].contains(lowered) {
            return lowered + trimmed.dropFirst(firstWord.count)
        }
        let words = trimmed.split(separator: " ")
        let isAcronym = firstWord.count > 1 && firstWord == firstWord.uppercased()
        let hasNumber = words.contains { $0.contains(where: \.isNumber) }
        guard !isAcronym, !hasNumber else { return "the " + trimmed }
        return "the " + firstWord.prefix(1).lowercased() + trimmed.dropFirst(1)
    }

    /// "Danny's", "Chris'".
    static func possessive(_ name: String) -> String {
        name.hasSuffix("s") ? name + "'" : name + "'s"
    }
}

private extension ScheduleDay.ItemKind {
    /// Blocks before turns before lessons at the same time.
    var rowRank: Int {
        switch self {
        case .block: 0
        case .turn: 1
        case .lesson: 2
        case .halfList: 3
        }
    }
}
