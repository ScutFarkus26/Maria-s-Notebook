// ScheduleDay.swift
// One day of the Schedules lanes as `ScheduleDayResolver` worked it out: the
// lanes and their items in time order, whether the day changed, the warnings,
// and what each lane has at a moment. Plain values; builds for iOS 18.

import Foundation

/// A child away from class for all or part of a day, from attendance: absent
/// (`fromMinute` nil), or leaving early at `fromMinute` (minutes after
/// midnight), planned (`leavesAt`) or already gone (Left Early).
nonisolated struct ScheduleChildAway: Sendable, Equatable {
    /// Upper-cased.
    let studentID: String
    let fromMinute: Int?

    init(studentID: String, fromMinute: Int?) {
        self.studentID = studentID.uppercased()
        self.fromMinute = fromMinute
    }

    /// Whether she is away during a lesson starting at `lessonStart` and
    /// lasting `LessonLength.assumedMinutes`.
    func isAway(duringLessonAt lessonStart: Int) -> Bool {
        guard let fromMinute else { return true }
        return lessonStart + LessonLength.assumedMinutes > fromMinute
    }

    /// Whether she is away for some of `half`: she leaves in it or before.
    func isAway(in half: ScheduleDayHalf) -> Bool {
        guard let fromMinute else { return true }
        return half == .afternoon || fromMinute < ScheduleDayHalf.noon
    }
}

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
        /// guide's lessons: during it, for a lesson with a set time
        /// (`lessonMinute`, checked with `TimetableBlockValues.overlaps`), or
        /// that half, for one without.
        case childWithPerson(
            studentID: String, personLaneID: UUID, personName: String, blockID: UUID,
            blockValues: TimetableBlockValues, lessonID: UUID, half: ScheduleDayHalf, lessonMinute: Int?
        )
        /// An adolescents-only lesson with no turn in the adolescent room that half.
        case adolescentLessonWithoutTurn(lessonID: UUID, lessonTitle: String?, half: ScheduleDayHalf)
        /// A set-time lesson, not adolescents-only, that overlaps the guide's
        /// turn (`TimetableBlockValues.overlaps`).
        case lessonDuringTurn(
            lessonID: UUID, lessonTitle: String?, minute: Int, turnID: UUID, turnValues: TimetableBlockValues
        )
        /// The guide is out (Out Today) with lessons planned: they're set
        /// aside, and this one warning stands for them all.
        case guideOut(lessonCount: Int)
        /// Two of the guide's lessons with set times less than
        /// `LessonLength.assumedMinutes` apart: he can give only one.
        case lessonsOverlap(first: LessonMention, second: LessonMention)
        /// A child in two people's blocks that overlap.
        case childInTwoBlocks(studentID: String, first: BlockMention, second: BlockMention)
        /// A person with two blocks or turns at once.
        case personInTwoBlocks(laneID: UUID, personName: String, first: BlockMention, second: BlockMention)
        /// A child in one of the guide's lessons is absent (`fromMinute` nil)
        /// or leaves early: during it, for a lesson with a set time; in that
        /// half or before it, for one without.
        case childAwayFromClass(
            studentID: String, fromMinute: Int?, lessonID: UUID, half: ScheduleDayHalf, lessonMinute: Int?
        )

        /// The lesson it's about, for a tap that scrolls to it; nil when it
        /// is about no one lesson.
        var lessonID: UUID? {
            switch self {
            case .childWithPerson(_, _, _, _, _, let id, _, _): id
            case .adolescentLessonWithoutTurn(let id, _, _): id
            case .lessonDuringTurn(let id, _, _, _, _): id
            case .lessonsOverlap(let first, _): first.id
            case .childAwayFromClass(_, _, let id, _, _): id
            case .guideOut, .childInTwoBlocks, .personInTwoBlocks: nil
            }
        }

        /// What the Schedules page says. `name` gives a child's short name
        /// ("Lucy T"); a child it doesn't know reads "A child".
        func text(name: (String) -> String?) -> String {
            switch self {
            case let .childWithPerson(studentID, _, personName, _, values, _, half, lessonMinute):
                let child = name(studentID) ?? "A child"
                let range = TimetableDay.rangeText(values)
                guard let lessonMinute else { return "\(child) is with \(personName) \(range) \(half.thisHalf)." }
                return "\(child) is with \(personName) \(range), during your "
                    + "\(TimetableDay.clockText(lessonMinute)) lesson."
            case let .adolescentLessonWithoutTurn(_, title, half):
                let lesson = title.map { "\($0) is" } ?? "A lesson planned"
                return "\(lesson) for adolescents only, but you have no turn in the adolescent room \(half.thisHalf)."
            case let .lessonDuringTurn(_, title, minute, _, values):
                let lesson = title ?? "A lesson"
                return "\(lesson) at \(TimetableDay.clockText(minute)) is during your turn in the adolescent room "
                    + "(\(TimetableDay.rangeText(values)))."
            case let .guideOut(count):
                return count == 1 ? "You're out; 1 lesson is planned." : "You're out; \(count) lessons are planned."
            case let .lessonsOverlap(first, second):
                return "\(first.title ?? "A lesson") at \(TimetableDay.clockText(first.minute)) and "
                    + "\(second.title ?? "another lesson") at \(TimetableDay.clockText(second.minute)) overlap."
            case let .childInTwoBlocks(studentID, first, second):
                let child = name(studentID) ?? "A child"
                return "\(child) is in two groups at once: \(first.text) and \(second.text)."
            case let .personInTwoBlocks(_, personName, first, second):
                return "\(personName) has two things at once: \(first.text) and \(second.text)."
            case let .childAwayFromClass(studentID, fromMinute, _, half, lessonMinute):
                let child = name(studentID) ?? "A child"
                let away = fromMinute.map { "leaves at \(TimetableDay.clockText($0))" } ?? "is absent"
                guard let lessonMinute else { return "\(child) \(away), and is in a lesson planned \(half.thisHalf)." }
                return "\(child) \(away), and is in your \(TimetableDay.clockText(lessonMinute)) lesson."
            }
        }

        var sortMinute: Int {
            switch self {
            case let .childWithPerson(_, _, _, _, values, _, _, _): values.startMinute
            case let .adolescentLessonWithoutTurn(_, _, half): half.listMinute
            case let .lessonDuringTurn(_, _, minute, _, _): minute
            case .guideOut: -1
            case let .lessonsOverlap(first, _): first.minute
            case let .childInTwoBlocks(_, _, second), let .personInTwoBlocks(_, _, _, second):
                second.values.startMinute
            case let .childAwayFromClass(_, fromMinute, _, half, lessonMinute):
                lessonMinute ?? fromMinute ?? half.listMinute
            }
        }

        var sortKey: String {
            switch self {
            case let .childWithPerson(studentID, _, _, blockID, _, _, _, _): "0\(blockID.uuidString)\(studentID)"
            case let .adolescentLessonWithoutTurn(id, _, _): "1\(id.uuidString)"
            case let .lessonDuringTurn(id, _, _, _, _): "2\(id.uuidString)"
            case .guideOut: "3"
            case let .lessonsOverlap(first, second): "4\(first.id.uuidString)\(second.id.uuidString)"
            case let .childInTwoBlocks(studentID, first, second):
                "5\(first.blockID.uuidString)\(second.blockID.uuidString)\(studentID)"
            case let .personInTwoBlocks(laneID, _, first, second):
                "6\(laneID.uuidString)\(first.blockID.uuidString)\(second.blockID.uuidString)"
            case let .childAwayFromClass(studentID, _, lessonID, _, _): "7\(lessonID.uuidString)\(studentID)"
            }
        }
    }

    /// A lesson named in a warning, with its set time.
    struct LessonMention: Sendable, Equatable {
        let id: UUID
        let title: String?
        let minute: Int
    }

    /// A block named in a warning: "Morah Devora's Reading 9:15–9:45".
    struct BlockMention: Sendable, Equatable {
        let blockID: UUID
        /// The lane it is in, or the room for a turn.
        let laneName: String
        let values: TimetableBlockValues

        /// "Morah Devora's Reading 9:15–9:45", "Our class 9:15–9:45".
        var text: String {
            let range = TimetableDay.rangeText(values)
            let title = values.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let lane = laneName.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { return lane.isEmpty ? range : "\(lane) \(range)" }
            return lane.isEmpty ? "\(title) \(range)" : "\(lane)'s \(title) \(range)"
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
    /// The blocks cancelled for this day only, with their every-week values,
    /// so each cancel can be taken back on its own.
    var cancelledBlocks: [Block] = []
    /// The children away from class that day (absent, or leaving early), as
    /// the day was worked out with them.
    var childrenAway: [ScheduleChildAway] = []
    /// The guide's lessons set aside because he is out (Out Today).
    var setAsideLessons: [Lesson] = []

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
