// TimetableValues.swift
// The plain values Schedules works in: the kinds of lane and change, the
// halves of the day, a block's editable values, and the snapshots the day is
// worked out from (`ScheduleDayResolver`). No Core Data here, so the notebook,
// the Daybook Assistant and MCP all hand the resolver the same shapes.

import Foundation

/// What a lane is: a room with its own timetable, or a person.
nonisolated enum TimetableLaneKind: String, Sendable, CaseIterable {
    case room
    case person
}

/// What one day's change does (`CDTimetableChange.kindRaw`).
nonisolated enum TimetableChangeKind: String, Sendable, CaseIterable {
    /// The block isn't on that day.
    case cancelled
    /// The block has other values that day.
    case changed
    /// The person is out that day: their blocks are off, and their turns in a
    /// room read "Out".
    case out
}

/// Morning or afternoon (`CDTimetableBooking.halfRaw`). Morning is before noon.
nonisolated enum ScheduleDayHalf: String, Sendable, CaseIterable, Comparable {
    case morning
    case afternoon

    /// Minutes after midnight at which the afternoon begins.
    static let noon = 12 * 60

    /// The half a time of day falls in.
    init(minute: Int) {
        self = minute < Self.noon ? .morning : .afternoon
    }

    /// Where the half's ordered list of lessons sits among the day's times:
    /// its base hour, where the planner puts it (`DayPeriod.baseHour`).
    var listMinute: Int {
        switch self {
        case .morning: UIConstants.morningHour * 60
        case .afternoon: UIConstants.afternoonHour * 60
        }
    }

    /// "this morning" or "this afternoon", for notes and warnings.
    var thisHalf: String {
        switch self {
        case .morning: "this morning"
        case .afternoon: "this afternoon"
        }
    }

    static func < (lhs: ScheduleDayHalf, rhs: ScheduleDayHalf) -> Bool {
        lhs == .morning && rhs == .afternoon
    }
}

/// What can be set on a block, and what a day's "changed" replaces in full.
nonisolated struct TimetableBlockValues: Sendable, Equatable {
    /// Minutes after midnight.
    var startMinute: Int
    var lengthMinutes: Int
    var title: String
    var note: String
    /// The person lane teaching this block (a turn in a room), if any.
    var teacherLaneID: UUID?
    /// Who teaches it when that isn't a person lane.
    var teacherName: String
    /// The children, as student ID strings.
    var studentIDs: [String]

    init(
        startMinute: Int,
        lengthMinutes: Int = 30,
        title: String = "",
        note: String = "",
        teacherLaneID: UUID? = nil,
        teacherName: String = "",
        studentIDs: [String] = []
    ) {
        self.startMinute = startMinute
        self.lengthMinutes = lengthMinutes
        self.title = title
        self.note = note
        self.teacherLaneID = teacherLaneID
        self.teacherName = teacherName
        self.studentIDs = studentIDs
    }

    /// Minutes after midnight when the block ends.
    var endMinute: Int { startMinute + max(lengthMinutes, 0) }

    /// Whether `minute` falls inside the block (its end excluded).
    func contains(minute: Int) -> Bool {
        minute >= startMinute && minute < endMinute
    }
}

// MARK: - Snapshots

/// One lane, as the resolver reads it.
nonisolated struct TimetableLaneSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var kind: TimetableLaneKind
    /// The one person lane that reads the guide's planned lessons.
    var isGuide: Bool
    var sortOrder: Int
    var colorRaw: String

    init(
        id: UUID = UUID(),
        name: String,
        kind: TimetableLaneKind,
        isGuide: Bool = false,
        sortOrder: Int = 0,
        colorRaw: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isGuide = isGuide
        self.sortOrder = sortOrder
        self.colorRaw = colorRaw
    }
}

/// One block, weekly or one-off, as the resolver reads it.
nonisolated struct TimetableBlockSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    var laneID: UUID?
    /// The weekday a weekly block is on; nil for a one-off.
    var weekday: Weekday?
    /// The day a one-off is on (start of day); nil for a weekly block.
    var onDay: Date?
    var values: TimetableBlockValues
    /// The first and last days a weekly block applies; nil is open-ended.
    var validFrom: Date?
    var validUntil: Date?

    init(
        id: UUID = UUID(),
        laneID: UUID?,
        weekday: Weekday? = nil,
        onDay: Date? = nil,
        values: TimetableBlockValues,
        validFrom: Date? = nil,
        validUntil: Date? = nil
    ) {
        self.id = id
        self.laneID = laneID
        self.weekday = weekday
        self.onDay = onDay
        self.values = values
        self.validFrom = validFrom
        self.validUntil = validUntil
    }

    var isOneOff: Bool { onDay != nil }
}

/// One day's change, as the resolver reads it.
nonisolated struct TimetableChangeSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    var day: Date?
    /// Nil for a kind this build doesn't know (a later build's), which is ignored.
    var kind: TimetableChangeKind?
    /// The block cancelled or changed.
    var blockID: UUID?
    /// The person lane that is out.
    var laneID: UUID?
    /// The replacement values, for "changed".
    var values: TimetableBlockValues
    var modifiedAt: Date?

    init(
        id: UUID = UUID(),
        day: Date?,
        kind: TimetableChangeKind?,
        blockID: UUID? = nil,
        laneID: UUID? = nil,
        values: TimetableBlockValues = TimetableBlockValues(startMinute: 0),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.day = day
        self.kind = kind
        self.blockID = blockID
        self.laneID = laneID
        self.values = values
        self.modifiedAt = modifiedAt
    }
}

/// One of the guide's planned lessons on the day. In the notebook and MCP it
/// comes from the presentation, with its title; on the Daybook Assistant from
/// a `CDTimetableBooking`, which has no title, so none can ever reach a screen
/// there.
nonisolated struct ScheduleLessonSnapshot: Sendable, Equatable, Identifiable {
    /// The planned presentation's ID.
    let id: UUID
    /// The lesson's name; nil on the Assistant.
    var title: String?
    var half: ScheduleDayHalf
    /// A set time, minutes after midnight; nil when only a half was planned.
    var minute: Int?
    /// Its place in the half, as the guide ordered it.
    var order: Int
    var studentIDs: [String]

    init(
        id: UUID,
        title: String? = nil,
        half: ScheduleDayHalf,
        minute: Int? = nil,
        order: Int = 0,
        studentIDs: [String]
    ) {
        self.id = id
        self.title = title
        self.half = minute.map(ScheduleDayHalf.init(minute:)) ?? half
        self.minute = minute
        self.order = order
        self.studentIDs = studentIDs
    }
}

// MARK: - Days

nonisolated enum TimetableDay {
    /// Calendar weekday numbers (1 = Sunday) to `Weekday` raw values, read
    /// here rather than through `Weekday`'s own members, which belong to the
    /// main actor.
    private static let weekdayRaws = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// The weekday `day` falls on in `calendar`.
    static func weekday(of day: Date, calendar: Calendar = AppCalendar.shared) -> Weekday? {
        let number = calendar.component(.weekday, from: day)
        guard (1...7).contains(number) else { return nil }
        return Weekday(rawValue: weekdayRaws[number - 1])
    }

    /// Minutes after midnight of `date` in `calendar`.
    static func minute(of date: Date, calendar: Calendar = AppCalendar.shared) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// "9:00", "1:30": a time of day as a school schedule prints it, without
    /// AM or PM.
    static func clockText(_ minute: Int) -> String {
        let wrapped = ((minute % 1440) + 1440) % 1440
        let hour = wrapped / 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let minutes = wrapped % 60
        return "\(hour12):" + (minutes < 10 ? "0\(minutes)" : "\(minutes)")
    }

    /// "9:00–9:45".
    static func rangeText(_ values: TimetableBlockValues) -> String {
        "\(clockText(values.startMinute))–\(clockText(values.endMinute))"
    }
}
