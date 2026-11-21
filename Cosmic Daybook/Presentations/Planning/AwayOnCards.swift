// AwayOnCards.swift
// What a Scheduled card, its time picker and the lesson's sheet say about
// children away with a co-teacher (docs/Plans/Plan - Co-teacher times when
// scheduling.md, decisions 4–6), worked out from the day's `AwayDay` and the
// lesson's children. Plain values in, plain values out: the planner loads the
// days once for the whole strip (`WeekPlanSection.refreshAwayDays`), and the
// sheet loads one day when its picker opens, so nothing here fetches.

import Foundation

nonisolated enum AwayOnCards {

    /// The line under a card's children.
    struct Note: Equatable, Sendable {
        /// "Lucy T leaves at 9:50 for Morah Devora", or for a lesson with no
        /// set time, "Lucy T is away 9:50–10:20".
        let line: String
        /// A set time that overlaps a group: the chip turns amber and the day's
        /// badge counts it. A lesson with no set time is never a clash, since
        /// it may be given around the group.
        let isClash: Bool
    }

    /// The card's note for a lesson with `children` at `setMinute` (nil for
    /// no set time, which is read against the groups of its `half`).
    static func note(
        in day: AwayDay,
        children: [String],
        setMinute: Int?,
        half: DayPeriod,
        name: (String) -> String?
    ) -> Note? {
        guard !day.isEmpty else { return nil }
        // Out Today: no lesson that day can be given, at a set time or not.
        if day.guideIsOut { return Note(line: AwayText.outLine, isClash: true) }
        if let setMinute {
            let clashes = day.clashes(children: children, start: setMinute)
            if let line = AwayText.clashLine(clashes, start: setMinute, name: name) {
                return Note(line: line, isClash: true)
            }
            return day.turnClash(children: children, start: setMinute)
                .map { Note(line: AwayText.turnLine($0), isClash: true) }
        }
        let scheduleHalf: ScheduleDayHalf = half == .morning ? .morning : .afternoon
        let clashes = day.away(children: children, in: scheduleHalf)
        return AwayText.untimedLine(clashes, half: scheduleHalf, name: name).map { Note(line: $0, isClash: false) }
    }

    /// What the time picker shows for a lesson with `children`: the Away list
    /// (groups, children away from class, then the guide's turns), a sentence
    /// on each quick time that overlaps one, the Everyone's free starts and
    /// the "Free all…" words; on a day he is out, only that. Nil when nothing
    /// touches the lesson that day, so the picker draws as it always has
    /// (decision 4).
    /// `ownStarts` are the day's other lessons' set times.
    static func pickerAway(
        in day: AwayDay,
        children: [String],
        ownStarts: some Sequence<Int>,
        name: (String) -> String?
    ) -> LessonTimeAway? {
        guard day.touches(children: children) else { return nil }
        if day.guideIsOut { return LessonTimeAway(rows: [AwayText.outLine]) }
        let away = day.away(children: children)
        let turns = day.busyTurns(children: children)
        var sentences: [Int: String] = [:]
        for minute in LessonTimeChoices.morning + LessonTimeChoices.afternoon {
            let clashes = day.clashes(children: children, start: minute)
            if let line = AwayText.clashLine(clashes, start: minute, name: name) {
                sentences[minute] = line
            } else if let turn = day.turnClash(children: children, start: minute) {
                sentences[minute] = AwayText.turnLine(turn)
            }
        }
        return LessonTimeAway(
            rows: away.map { AwayText.awayRow($0, name: name) } + turns.map(AwayText.turnRow),
            sentences: sentences,
            suggestions: day.freeStarts(children: children, ownStarts: Array(ownStarts)),
            freeWords: AwayText.freeWords(day.freeHalves(children: children))
        )
    }

    /// Short names by upper-cased student ID, the way `AwayText` asks for them.
    static func names(_ students: [CDStudent]) -> [String: String] {
        Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString.uppercased(), student.shortName) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
