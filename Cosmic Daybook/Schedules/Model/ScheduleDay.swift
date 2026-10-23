// ScheduleDay.swift
// One day of the Schedules lanes as `ScheduleDayResolver` worked it out: the
// lanes and their items in time order, whether the day changed, the warnings,
// and what each lane has at a moment. Plain values; builds for iOS 18.

import Foundation

/// One day of the Schedules lanes, as `ScheduleDayResolver` worked it out.
nonisolated struct ScheduleDay: Sendable, Equatable {

    /// A block on the day, with that day's values.
    struct Block: Sendable, Equatable, Identifiable {
        let id: UUID
        /// The lane the block belongs to (the room, for a turn).
        let laneID: UUID
        /// The day's values: a "changed" change's, when there is one.
        var values: TimetableBlockValues
        var isOneOff: Bool
        /// Changed for this day only.
        var isChanged: Bool
        /// The person lane teaching it, when it's a turn.
        var teacherLaneID: UUID?
        /// That person is out today: the block reads "Out".
        var teacherIsOut: Bool
        /// The guide's adolescents-only lessons placed in this turn.
        var lessons: [Lesson] = []

        /// Changed for the day in any way: a one-off, or one day's values.
        var isDayChange: Bool { isOneOff || isChanged }

        /// The block's own children and those of the lessons placed in it,
        /// each once, in that order.
        var studentIDs: [String] {
            var seen = Set<String>()
            return (values.studentIDs + lessons.flatMap(\.snapshot.studentIDs)).filter {
                seen.insert($0.uppercased()).inserted
            }
        }
    }

    /// One of the guide's lessons on the day.
    struct Lesson: Sendable, Equatable, Identifiable {
        let snapshot: ScheduleLessonSnapshot
        /// Every child is adolescent-level.
        var isAdolescentsOnly: Bool
        /// "No turn in the adolescent room this morning", when that's so.
        var note: String?

        var id: UUID { snapshot.id }
    }

    /// What a lane shows.
    enum ItemKind: Sendable, Equatable {
        /// The lane's own block.
        case block(Block)
        /// A room's block this person teaches.
        case turn(Block)
        /// One of the guide's lessons, at its set time.
        case lesson(Lesson)
        /// The guide's lessons for a half, in his order.
        case halfList(ScheduleDayHalf, [Lesson])
    }

    struct Item: Sendable, Equatable, Identifiable {
        let kind: ItemKind

        /// Unique within its lane.
        var id: String {
            switch kind {
            case .block(let block): "block-\(block.id.uuidString)"
            case .turn(let block): "turn-\(block.id.uuidString)"
            case .lesson(let lesson): "lesson-\(lesson.id.uuidString)"
            case .halfList(let half, _): "list-\(half.rawValue)"
            }
        }

        /// Minutes after midnight it starts at; a half's list sits at its base hour.
        var startMinute: Int {
            switch kind {
            case .block(let block), .turn(let block): block.values.startMinute
            case .lesson(let lesson): lesson.snapshot.minute ?? lesson.snapshot.half.listMinute
            case .halfList(let half, _): half.listMinute
            }
        }

        /// Minutes after midnight it ends at; nil for lessons, which have no length.
        var endMinute: Int? {
            switch kind {
            case .block(let block), .turn(let block): block.values.endMinute
            case .lesson, .halfList: nil
            }
        }

        var block: Block? {
            switch kind {
            case .block(let block), .turn(let block): block
            case .lesson, .halfList: nil
            }
        }

        /// Blocks before lessons at the same time.
        var rank: Int {
            switch kind {
            case .block: 0
            case .turn: 1
            case .lesson: 2
            case .halfList: 3
            }
        }
    }

    struct Lane: Sendable, Equatable, Identifiable {
        let lane: TimetableLaneSnapshot
        /// In time order.
        var items: [Item]
        /// The person is out today (Out Today).
        var isOut: Bool

        var id: UUID { lane.id }
    }

    /// What one lane has at a moment, for the Assistant's Now card.
    struct NowEntry: Sendable, Equatable {
        let lane: TimetableLaneSnapshot
        /// The block or turn under way, if any.
        let block: Block?
        /// The room a turn is in; nil for the lane's own block.
        let roomLaneID: UUID?
        let isOut: Bool

        /// When the block under way ends, minutes after midnight.
        var until: Int? { block?.values.endMinute }
    }

    /// A gentle warning; it never blocks anything.
    enum Warning: Sendable, Equatable {
        /// A child in a block of another person's lane is also in one of the
        /// guide's lessons that half.
        case childWithPerson(
            studentID: String, personLaneID: UUID, personName: String, blockID: UUID,
            blockValues: TimetableBlockValues, lessonID: UUID, half: ScheduleDayHalf
        )
        /// An adolescents-only lesson with no turn in the adolescent room that half.
        case adolescentLessonWithoutTurn(lessonID: UUID, lessonTitle: String?, half: ScheduleDayHalf)
        /// A set-time lesson, not adolescents-only, during the guide's turn.
        case lessonDuringTurn(
            lessonID: UUID, lessonTitle: String?, minute: Int, turnID: UUID, turnValues: TimetableBlockValues
        )

        /// The lesson it's about, for a tap that scrolls to it.
        var lessonID: UUID {
            switch self {
            case .childWithPerson(_, _, _, _, _, let id, _): id
            case .adolescentLessonWithoutTurn(let id, _, _): id
            case .lessonDuringTurn(let id, _, _, _, _): id
            }
        }

        /// What the Schedules page says. `name` gives a child's short name
        /// ("Lucy T"); a child it doesn't know reads "A child".
        func text(name: (String) -> String?) -> String {
            switch self {
            case let .childWithPerson(studentID, _, personName, _, values, _, half):
                let child = name(studentID) ?? "A child"
                return "\(child) is with \(personName) \(TimetableDay.rangeText(values)) \(half.thisHalf)."
            case let .adolescentLessonWithoutTurn(_, title, half):
                let lesson = title.map { "\($0) is" } ?? "A lesson planned"
                return "\(lesson) for adolescents only, but you have no turn in the adolescent room \(half.thisHalf)."
            case let .lessonDuringTurn(_, title, minute, _, values):
                let lesson = title ?? "A lesson"
                return "\(lesson) at \(TimetableDay.clockText(minute)) is during your turn in the adolescent room "
                    + "(\(TimetableDay.rangeText(values)))."
            }
        }

        var sortMinute: Int {
            switch self {
            case let .childWithPerson(_, _, _, _, values, _, _): values.startMinute
            case let .adolescentLessonWithoutTurn(_, _, half): half.listMinute
            case let .lessonDuringTurn(_, _, minute, _, _): minute
            }
        }

        var sortKey: String {
            switch self {
            case let .childWithPerson(studentID, _, _, blockID, _, _, _): "0\(blockID.uuidString)\(studentID)"
            case let .adolescentLessonWithoutTurn(id, _, _): "1\(id.uuidString)"
            case let .lessonDuringTurn(id, _, _, _, _): "2\(id.uuidString)"
            }
        }
    }

    /// The day (start of day).
    let day: Date
    /// False on a day with no school: every lane is empty and the day reads
    /// "No school".
    let isSchoolDay: Bool
    /// In `sortOrder`.
    let lanes: [Lane]
    /// How many changes the day has: changed or cancelled blocks, people out
    /// and one-offs ("1 change today").
    let changeCount: Int
    let warnings: [Warning]

    var isChanged: Bool { changeCount > 0 }

    func lane(_ id: UUID) -> Lane? {
        lanes.first { $0.lane.id == id }
    }

    /// What each lane has at `minute` (minutes after midnight), in lane
    /// order: the block or turn under way, the one that began last when two
    /// overlap. Lessons have no length, so they're never under way.
    func now(at minute: Int) -> [NowEntry] {
        lanes.map { lane in
            let current = lane.items
                .filter { $0.block?.values.contains(minute: minute) == true }
                .max { lhs, rhs in lhs.startMinute < rhs.startMinute }
            let roomLaneID: UUID? = if case .turn(let block) = current?.kind { block.laneID } else { nil }
            return NowEntry(lane: lane.lane, block: current?.block, roomLaneID: roomLaneID, isOut: lane.isOut)
        }
    }
}
