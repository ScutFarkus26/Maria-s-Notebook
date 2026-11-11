// AwayText.swift
// Every sentence about children away with a co-teacher: the time picker's
// Away rows and marks, the card's line (timed and untimed), the "Free all…"
// words, and MCP's scheduling replies (plan "Co-teacher times when
// scheduling", decisions 4, 6 and 8). Plain values in, words out; times are
// written as Schedules writes them ("9:50", "9:50–10:20").
//
// `name` gives a child's short name ("Lucy T") for an upper-cased student ID;
// a child it doesn't know reads "A child".

import Foundation

nonisolated enum AwayText {

    // MARK: - Fixed words

    /// The picker's row of suggested times.
    static let everyonesFreeTitle = "Everyone's free"
    /// The picker's list of groups.
    static let awayTitle = "Away"
    /// The planner's legend line for the mark.
    static let legend = "A child is with another teacher"
    /// What VoiceOver adds to a clashing time chip.
    static let chipSpoken = "a child is with another teacher then"

    /// "2 with a child away": the away part of a day badge's count.
    static func badgeCount(_ count: Int) -> String {
        "\(count) with a child away"
    }

    /// "Free all morning" or "Free all afternoon", when exactly one half has
    /// no group for the lesson's children; nil otherwise (with both halves
    /// free nobody is away, and the picker shows nothing new).
    static func freeWords(_ freeHalves: [ScheduleDayHalf]) -> String? {
        guard freeHalves.count == 1, let half = freeHalves.first else { return nil }
        return "Free all \(half.word)"
    }

    // MARK: - The picker

    /// "9:15–9:45 · Lucy T, Ora P · Miss Nicole": one group in the Away list.
    static func awayRow(_ clash: AwayClash, name: (String) -> String?) -> String {
        let children = childList(clash.studentIDs, name: name, joiner: ", ")
        return "\(range(clash.block)) · \(children) · \(clash.block.personName)"
    }

    // MARK: - A lesson with a set time

    /// The line for a lesson starting at `start` that overlaps `clashes`, as
    /// the card shows it and a marked quick time says it; nil when none.
    /// - One group, one or two children: "Lucy T leaves at 9:50 for Morah
    ///   Devora" (the group starts during the lesson) or "Lucy T and Ora P are
    ///   with Miss Nicole until 9:45" (already there when it starts).
    /// - One child, more than one group: "Lucy T is away during this lesson".
    /// - Otherwise: "3 children are away during this lesson".
    static func clashLine(_ clashes: [AwayClash], start: Int, name: (String) -> String?) -> String? {
        guard let first = clashes.first else { return nil }
        let children = distinctChildren(clashes)
        if clashes.count == 1, children.count <= 2 {
            let who = childList(first.studentIDs, name: name)
            let plural = first.studentIDs.count > 1
            if first.block.startMinute > start {
                return "\(who) \(plural ? "leave" : "leaves") at \(TimetableDay.clockText(first.block.startMinute)) "
                    + "for \(first.block.personName)"
            }
            return "\(who) \(plural ? "are" : "is") with \(first.block.personName) "
                + "until \(TimetableDay.clockText(first.block.endMinute))"
        }
        if children.count == 1 {
            return "\(childName(children[0], name: name)) is away during this lesson"
        }
        return "\(children.count) children are away during this lesson"
    }

    // MARK: - A lesson with no set time

    /// The quiet line for a lesson with no set time whose children are in
    /// `clashes` that half; nil when none.
    /// - One group, one or two children: "Lucy T is away 9:50–10:20",
    ///   "Leora F and Naomi F are away 9:50–10:20".
    /// - One child, more than one group: "Lucy T is away part of the morning".
    /// - Otherwise: "2 children are away part of the morning".
    static func untimedLine(
        _ clashes: [AwayClash], half: ScheduleDayHalf, name: (String) -> String?
    ) -> String? {
        guard let first = clashes.first else { return nil }
        let children = distinctChildren(clashes)
        if clashes.count == 1, children.count <= 2 {
            let plural = first.studentIDs.count > 1
            return "\(childList(first.studentIDs, name: name)) \(plural ? "are" : "is") away \(range(first.block))"
        }
        if children.count == 1 {
            return "\(childName(children[0], name: name)) is away part of the \(half.word)"
        }
        return "\(children.count) children are away part of the \(half.word)"
    }

    // MARK: - MCP

    /// The sentences `schedule_presentation` and `reschedule_presentation`
    /// add for the day they scheduled, one per group: "Lucy T is with Morah
    /// Devora 9:50–10:20." for a lesson at a set time it overlaps, "Lucy T is
    /// away 9:50–10:20 that morning." for an untimed lesson in that half.
    static func scheduledLines(
        _ clashes: [AwayClash], lessonMinute: Int?, name: (String) -> String?
    ) -> [String] {
        clashes.map { clash in
            let who = childList(clash.studentIDs, name: name)
            let plural = clash.studentIDs.count > 1
            if lessonMinute != nil {
                return "\(who) \(plural ? "are" : "is") with \(clash.block.personName) \(range(clash.block))."
            }
            return "\(who) \(plural ? "are" : "is") away \(range(clash.block)) that \(clash.block.half.word)."
        }
    }

    // MARK: - Pieces

    /// "9:50–10:20".
    static func range(_ block: AwayBlock) -> String {
        "\(TimetableDay.clockText(block.startMinute))–\(TimetableDay.clockText(block.endMinute))"
    }

    /// "Lucy T", "Lucy T and Ora P", "Lucy T, Ora P and Leora F"; with
    /// `joiner` ", " every name is joined by commas.
    static func childList(_ ids: [String], name: (String) -> String?, joiner: String? = nil) -> String {
        let names = ids.map { childName($0, name: name) }
        if let joiner { return names.joined(separator: joiner) }
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func childName(_ id: String, name: (String) -> String?) -> String {
        let known = name(id.uppercased())?.trimmed() ?? ""
        return known.isEmpty ? "A child" : known
    }

    /// The children of `clashes`, each once, in order.
    private static func distinctChildren(_ clashes: [AwayClash]) -> [String] {
        AwayDay.keys(clashes.flatMap(\.studentIDs))
    }
}

private extension ScheduleDayHalf {
    /// "morning" or "afternoon".
    nonisolated var word: String {
        switch self {
        case .morning: "morning"
        case .afternoon: "afternoon"
        }
    }
}
