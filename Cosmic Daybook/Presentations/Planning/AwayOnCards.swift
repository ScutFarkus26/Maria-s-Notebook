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
        if let setMinute {
            let clashes = day.clashes(children: children, start: setMinute)
            return AwayText.clashLine(clashes, start: setMinute, name: name).map { Note(line: $0, isClash: true) }
        }
        let scheduleHalf: ScheduleDayHalf = half == .morning ? .morning : .afternoon
        let clashes = day.away(children: children, in: scheduleHalf)
        return AwayText.untimedLine(clashes, half: scheduleHalf, name: name).map { Note(line: $0, isClash: false) }
    }

    /// What the time picker shows for a lesson with `children`: the Away list,
    /// a sentence on each quick time that overlaps a group, the Everyone's
    /// free starts and the "Free all…" words. Nil when none of the children is
    /// away that day, so the picker draws as it always has (decision 4).
    /// `ownStarts` are the day's other lessons' set times.
    static func pickerAway(
        in day: AwayDay,
        children: [String],
        ownStarts: some Sequence<Int>,
        name: (String) -> String?
    ) -> LessonTimeAway? {
        let away = day.away(children: children)
        guard !away.isEmpty else { return nil }
        var sentences: [Int: String] = [:]
        for minute in LessonTimeChoices.morning + LessonTimeChoices.afternoon {
            let clashes = day.clashes(children: children, start: minute)
            if let line = AwayText.clashLine(clashes, start: minute, name: name) {
                sentences[minute] = line
            }
        }
        return LessonTimeAway(
            rows: away.map { AwayText.awayRow($0, name: name) },
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
