// ScheduleDayResolver.swift
// One day of the Schedules lanes, worked out once from plain values, so the
// notebook's page, Today, the Daybook Assistant and MCP show the same day.
// No Core Data, and it builds for iOS 18 (the Assistant compiles it).

import Foundation

/// Works out one day (`ScheduleDay`) from the lanes, the blocks, the day's
/// changes and the guide's planned lessons. Rules, in order:
/// 1. **No school** (the caller asks the school calendar): the day reads "No
///    school" and nothing else is shown.
/// 2. **Which blocks apply.** A one-off on the day, or a weekly block on the
///    day's weekday with `validFrom ≤ day ≤ validUntil` (either end open when nil).
/// 3. **The day's changes.** Cancelled hides a block, changed replaces its
///    values for the day (the newest change wins), and out cancels every block
///    in that person's lane and marks their turns in a room "Out". Any change,
///    or any one-off, marks the day changed.
/// 4. **Turns.** A room's block taught by a person lane also shows in that
///    person's lane. It is the same block, so a change to it shows in both.
/// 5. **The guide's lessons** go in the `isGuide` lane: a half's lessons in one
///    ordered list, a lesson with a set time at its time. A lesson whose
///    children are all adolescents goes into the guide's turn in the
///    adolescent room that half (or the turn its set time falls in); with no
///    turn that half it stays in the list with a note. A lesson that mixes
///    levels stays in the list. Only the adolescent room's blocks are those
///    turns (`isAdolescentRoom`), not a block he teaches in our class; when no
///    room's name says which it is, any room's are.
/// 6. **Warnings**, gentle: a child with another person in the same half as
///    one of the guide's lessons; an adolescents-only lesson with no turn that
///    half; a set-time lesson, not adolescents-only, during a guide's turn.
nonisolated enum ScheduleDayResolver {

    /// The note on an adolescents-only lesson with no turn that half.
    static func noTurnNote(_ half: ScheduleDayHalf) -> String {
        "No turn in the adolescent room \(half.thisHalf)"
    }

    /// Whether `lane` is the adolescent room, by its name ("Adolescent room",
    /// "Adolescents"): lanes carry no other mark of it.
    static func isAdolescentRoom(_ lane: TimetableLaneSnapshot) -> Bool {
        lane.kind == .room
            && lane.name.range(of: "adolescen", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Resolving

    static func resolve(_ input: Input) -> ScheduleDay {
        let day = input.calendar.startOfDay(for: input.day)
        let lanes = input.lanes.sorted(by: laneOrder)
        guard input.isSchoolDay else {
            return ScheduleDay(
                day: day, isSchoolDay: false,
                lanes: lanes.map { ScheduleDay.Lane(lane: $0, items: [], isOut: false) },
                changeCount: 0, warnings: []
            )
        }
        let context = DayContext(lanes: lanes, levels: input.studentLevels)
        var blocks = dayBlocks(input, day: day, context: context)
        let guideLane = lanes.first { $0.isGuide && $0.kind == .person }
        var placement = LessonPlacement()
        if let guideLane {
            placement = place(
                uniqueLessons(input.lessons), guideLane: guideLane,
                guideIsOut: blocks.outLanes.contains(guideLane.id), blocks: &blocks.blocks, context: context
            )
        }
        let warnings = childWarnings(
            blocks: blocks.blocks, context: context, guideLaneID: guideLane?.id, lessons: placement.all
        ) + placement.warnings
        return ScheduleDay(
            day: day, isSchoolDay: true,
            lanes: dayLanes(blocks: blocks, placement: placement, guideLane: guideLane, context: context),
            changeCount: blocks.changeCount, warnings: warnings.sorted(by: warningOrder),
            cancelledBlocks: blocks.cancelled
        )
    }

    /// Whether `block` is on `day` (rule 2).
    static func applies(_ block: TimetableBlockSnapshot, on day: Date, calendar: Calendar) -> Bool {
        if let onDay = block.onDay { return calendar.isDate(onDay, inSameDayAs: day) }
        guard let weekday = block.weekday, weekday == TimetableDay.weekday(of: day, calendar: calendar) else {
            return false
        }
        let start = calendar.startOfDay(for: day)
        if let from = block.validFrom, calendar.startOfDay(for: from) > start { return false }
        if let until = block.validUntil, calendar.startOfDay(for: until) < start { return false }
        return true
    }

    // MARK: - Steps

    /// The lanes, looked up, and each child's level by upper-cased ID.
    private struct DayContext {
        let lanesByID: [UUID: TimetableLaneSnapshot]
        let personIDs: Set<UUID>
        let roomIDs: Set<UUID>
        /// The rooms where a block the guide teaches is his turn for his
        /// adolescents' lessons: the adolescent room, or every room when no
        /// room's name says which it is.
        let turnRoomIDs: Set<UUID>
        let levels: [String: CDStudent.Level]

        init(lanes: [TimetableLaneSnapshot], levels: [String: CDStudent.Level]) {
            lanesByID = Dictionary(lanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            personIDs = Set(lanes.filter { $0.kind == .person }.map(\.id))
            roomIDs = Set(lanes.filter { $0.kind == .room }.map(\.id))
            let adolescentRooms = Set(lanes.filter(ScheduleDayResolver.isAdolescentRoom).map(\.id))
            turnRoomIDs = adolescentRooms.isEmpty ? roomIDs : adolescentRooms
            self.levels = Dictionary(
                levels.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { first, _ in first }
            )
        }
    }

    /// The day's blocks with the day's values (rules 2 and 3), in time order.
    private struct DayBlocks {
        var blocks: [ScheduleDay.Block] = []
        /// Cancelled for the day only, with their own values.
        var cancelled: [ScheduleDay.Block] = []
        var outLanes: Set<UUID> = []
        var changeCount = 0
    }

    private static func dayBlocks(_ input: Input, day: Date, context: DayContext) -> DayBlocks {
        let calendar = input.calendar
        let dayChanges = input.changes.filter { change in
            guard change.kind != nil, let changeDay = change.day else { return false }
            return calendar.isDate(changeDay, inSameDayAs: day)
        }
        var result = DayBlocks()
        result.outLanes = Set(dayChanges.compactMap { $0.kind == .out ? $0.laneID : nil })
            .intersection(context.personIDs)
        result.changeCount = result.outLanes.count
        var blockChange: [UUID: TimetableChangeSnapshot] = [:]
        for change in dayChanges where change.kind != .out {
            guard let blockID = change.blockID else { continue }
            if let kept = blockChange[blockID], !isNewer(change, than: kept) { continue }
            blockChange[blockID] = change
        }
        for block in input.blocks {
            guard let laneID = block.laneID, context.lanesByID[laneID] != nil,
                  !result.outLanes.contains(laneID), applies(block, on: day, calendar: calendar) else { continue }
            var values = block.values
            let change = blockChange[block.id]
            if change != nil || block.isOneOff { result.changeCount += 1 }
            if let change, change.kind != .cancelled { values = change.values }
            let teacher = values.teacherLaneID.flatMap { context.personIDs.contains($0) && $0 != laneID ? $0 : nil }
            let dayBlock = ScheduleDay.Block(
                id: block.id, laneID: laneID, values: values, isOneOff: block.isOneOff, isChanged: change != nil,
                teacherLaneID: teacher, teacherIsOut: teacher.map(result.outLanes.contains) ?? false
            )
            // A cancelled block is off the day, and kept aside to be brought back.
            if change?.kind == .cancelled {
                result.cancelled.append(dayBlock)
            } else {
                result.blocks.append(dayBlock)
            }
        }
        result.blocks.sort(by: blockOrder)
        result.cancelled.sort(by: blockOrder)
        return result
    }

    /// Each lane's items in time order (rule 4: a turn shows in its teacher's lane too).
    private static func dayLanes(
        blocks: DayBlocks, placement: LessonPlacement, guideLane: TimetableLaneSnapshot?, context: DayContext
    ) -> [ScheduleDay.Lane] {
        var itemsByLane: [UUID: [ScheduleDay.Item]] = [:]
        for block in blocks.blocks {
            itemsByLane[block.laneID, default: []].append(ScheduleDay.Item(kind: .block(block)))
            if let teacher = block.teacherLaneID, !block.teacherIsOut, context.roomIDs.contains(block.laneID) {
                itemsByLane[teacher, default: []].append(ScheduleDay.Item(kind: .turn(block)))
            }
        }
        if let guideLane {
            for lesson in placement.timed {
                itemsByLane[guideLane.id, default: []].append(ScheduleDay.Item(kind: .lesson(lesson)))
            }
            for half in ScheduleDayHalf.allCases {
                guard let list = placement.lists[half], !list.isEmpty else { continue }
                itemsByLane[guideLane.id, default: []].append(ScheduleDay.Item(kind: .halfList(half, list)))
            }
        }
        return context.lanesByID.values.sorted(by: laneOrder).map { lane in
            ScheduleDay.Lane(
                lane: lane,
                items: (itemsByLane[lane.id] ?? []).sorted(by: itemOrder),
                isOut: blocks.outLanes.contains(lane.id)
            )
        }
    }

    // MARK: - The guide's lessons (rule 5)

    private struct LessonPlacement {
        var timed: [ScheduleDay.Lesson] = []
        var lists: [ScheduleDayHalf: [ScheduleDay.Lesson]] = [:]
        var warnings: [ScheduleDay.Warning] = []
        /// Every lesson, wherever it went.
        var all: [ScheduleDay.Lesson] = []
    }

    /// The first copy of each lesson, in the guide's order.
    private static func uniqueLessons(_ lessons: [ScheduleLessonSnapshot]) -> [ScheduleLessonSnapshot] {
        var seen = Set<UUID>()
        return lessons.filter { seen.insert($0.id).inserted }.sorted { lhs, rhs in
            if lhs.half != rhs.half { return lhs.half < rhs.half }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.minute != rhs.minute { return (lhs.minute ?? -1) < (rhs.minute ?? -1) }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func place(
        _ lessons: [ScheduleLessonSnapshot],
        guideLane: TimetableLaneSnapshot,
        guideIsOut: Bool,
        blocks: inout [ScheduleDay.Block],
        context: DayContext
    ) -> LessonPlacement {
        // The guide's turns in the adolescent room, unless he's out.
        let turns = guideIsOut ? [] : blocks.indices.filter {
            blocks[$0].teacherLaneID == guideLane.id && context.turnRoomIDs.contains(blocks[$0].laneID)
        }
        var placement = LessonPlacement()
        for snapshot in lessons {
            let ids = snapshot.studentIDs
            let onlyAdolescents = !ids.isEmpty && ids.allSatisfy { context.levels[$0.uppercased()] == .adolescent }
            var lesson = ScheduleDay.Lesson(snapshot: snapshot, isAdolescentsOnly: onlyAdolescents)
            let halfTurns = turns.filter { ScheduleDayHalf(minute: blocks[$0].values.startMinute) == snapshot.half }
            let containing = snapshot.minute.flatMap { minute in
                turns.first { blocks[$0].values.contains(minute: minute) }
            }
            if onlyAdolescents, let turn = snapshot.minute == nil ? halfTurns.first : containing {
                blocks[turn].lessons.append(lesson)
                placement.all.append(lesson)
                continue
            }
            if onlyAdolescents, halfTurns.isEmpty, !guideIsOut {
                lesson.note = noTurnNote(snapshot.half)
                placement.warnings.append(.adolescentLessonWithoutTurn(
                    lessonID: snapshot.id, lessonTitle: snapshot.title, half: snapshot.half
                ))
            } else if !onlyAdolescents, let minute = snapshot.minute, let turn = containing {
                placement.warnings.append(.lessonDuringTurn(
                    lessonID: snapshot.id, lessonTitle: snapshot.title, minute: minute,
                    turnID: blocks[turn].id, turnValues: blocks[turn].values
                ))
            }
            if snapshot.minute != nil {
                placement.timed.append(lesson)
            } else {
                placement.lists[snapshot.half, default: []].append(lesson)
            }
            placement.all.append(lesson)
        }
        return placement
    }

    // MARK: - Warnings (rule 6)

    /// A child in a block of a person lane other than the guide's who is also
    /// in one of the guide's lessons that half: one warning per child and block.
    private static func childWarnings(
        blocks: [ScheduleDay.Block], context: DayContext, guideLaneID: UUID?, lessons: [ScheduleDay.Lesson]
    ) -> [ScheduleDay.Warning] {
        guard guideLaneID != nil, !lessons.isEmpty else { return [] }
        var lessonChildren: [ScheduleDayHalf: [String: UUID]] = [:]
        for lesson in lessons {
            let half = lesson.snapshot.half
            for id in lesson.snapshot.studentIDs where lessonChildren[half]?[id.uppercased()] == nil {
                lessonChildren[half, default: [:]][id.uppercased()] = lesson.id
            }
        }
        var warnings: [ScheduleDay.Warning] = []
        for block in blocks {
            guard let lane = context.lanesByID[block.laneID], lane.kind == .person, lane.id != guideLaneID else {
                continue
            }
            let half = ScheduleDayHalf(minute: block.values.startMinute)
            var seen = Set<String>()
            for child in block.values.studentIDs {
                let key = child.uppercased()
                guard seen.insert(key).inserted, let lessonID = lessonChildren[half]?[key] else { continue }
                warnings.append(.childWithPerson(
                    studentID: child, personLaneID: lane.id, personName: lane.name, blockID: block.id,
                    blockValues: block.values, lessonID: lessonID, half: half
                ))
            }
        }
        return warnings
    }

    // MARK: - Orders

    private static func laneOrder(_ lhs: TimetableLaneSnapshot, _ rhs: TimetableLaneSnapshot) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func blockOrder(_ lhs: ScheduleDay.Block, _ rhs: ScheduleDay.Block) -> Bool {
        if lhs.values.startMinute != rhs.values.startMinute { return lhs.values.startMinute < rhs.values.startMinute }
        if lhs.values.endMinute != rhs.values.endMinute { return lhs.values.endMinute < rhs.values.endMinute }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func itemOrder(_ lhs: ScheduleDay.Item, _ rhs: ScheduleDay.Item) -> Bool {
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lhs.id < rhs.id
    }

    private static func warningOrder(_ lhs: ScheduleDay.Warning, _ rhs: ScheduleDay.Warning) -> Bool {
        if lhs.sortMinute != rhs.sortMinute { return lhs.sortMinute < rhs.sortMinute }
        return lhs.sortKey < rhs.sortKey
    }

    /// The newer of two changes for one block and day: by `modifiedAt`, then `id`.
    private static func isNewer(_ lhs: TimetableChangeSnapshot, than rhs: TimetableChangeSnapshot) -> Bool {
        let left = lhs.modifiedAt ?? .distantPast
        let right = rhs.modifiedAt ?? .distantPast
        if left != right { return left > right }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}

extension ScheduleDayResolver {

    /// What the day is worked out from.
    struct Input: Sendable {
        var day: Date
        var lanes: [TimetableLaneSnapshot]
        /// Every block (the resolver picks the day's).
        var blocks: [TimetableBlockSnapshot]
        /// Changes (the resolver picks the day's).
        var changes: [TimetableChangeSnapshot]
        /// The guide's planned lessons that day.
        var lessons: [ScheduleLessonSnapshot]
        /// Each child's level, by student ID (any case).
        var studentLevels: [String: CDStudent.Level]
        /// False on a day the school calendar has no school.
        var isSchoolDay: Bool
        var calendar: Calendar

        init(
            day: Date,
            lanes: [TimetableLaneSnapshot],
            blocks: [TimetableBlockSnapshot],
            changes: [TimetableChangeSnapshot] = [],
            lessons: [ScheduleLessonSnapshot] = [],
            studentLevels: [String: CDStudent.Level] = [:],
            isSchoolDay: Bool = true,
            calendar: Calendar = AppCalendar.shared
        ) {
            self.day = day
            self.lanes = lanes
            self.blocks = blocks
            self.changes = changes
            self.lessons = lessons
            self.studentLevels = studentLevels
            self.isSchoolDay = isSchoolDay
            self.calendar = calendar
        }
    }
}
