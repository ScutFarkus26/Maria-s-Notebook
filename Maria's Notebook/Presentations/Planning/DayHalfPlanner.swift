// DayHalfPlanner.swift
// Which half of the day a scheduled presentation sits in, and how a day is
// numbered so that half survives every reorder.
//
// A scheduled presentation has no time — the guide plans an order, not a
// timetable — so `scheduledFor` carries that order as second-spaced offsets
// from a base hour. That leaves exactly one thing still worth saying about
// *when*: morning or afternoon. The base hour now says it. Morning items count
// up from 9, afternoon items from 2, and nothing new is stored: the halves are
// read back out of the hour. Nothing is added to the Core Data model either,
// which matters here — the model is CloudKit-mirrored and edited in place.
//
// Numbering per half rather than across the whole day is what keeps the two
// apart. Six morning lessons and one afternoon lesson are 9:00:00–9:00:05 and
// 14:00:00, so no amount of reordering can walk the morning run into the
// afternoon, and the day still sorts top to bottom in the order it will be
// taught — every morning offset is before noon and every afternoon one after.

import Foundation

// `DayPeriod` itself is declared in Planning/PlanningModels.swift, with the
// label, colour and base hour the planning screens already used.
extension DayPeriod {
    /// What a card shows: two characters, which is all a pill has room for
    /// beside a lesson title and a row of student chips. `label` is the spoken
    /// form, and what the menu offers.
    var abbreviation: String {
        switch self {
        case .morning: return "AM"
        case .afternoon: return "PM"
        }
    }

    /// The half an already-scheduled moment falls in.
    ///
    /// Noon is the only boundary that matters here, not the base hours: a
    /// deliberate 10:30 is still a morning, and the rows written before the
    /// halves existed sit at midnight, which reads as morning too — the same
    /// half the ordering base has always used.
    init(scheduledFor date: Date, using calendar: Calendar = AppCalendar.shared) {
        self = calendar.component(.hour, from: date) < 12 ? .morning : .afternoon
    }

    /// `date` moved into this half, at this half's base hour.
    ///
    /// The minute and second come along because that is where a presentation's
    /// position within its day is kept — 9:00:05 is the sixth lesson of the
    /// morning, and flipping it to the afternoon should make it the sixth
    /// there, not flatten it onto whatever is already at 2:00 sharp. The hour
    /// is not kept: there is no time here to preserve, and carrying a 10 across
    /// would turn a morning lesson into a 10pm one.
    func applied(to date: Date, using calendar: Calendar = AppCalendar.shared) -> Date {
        let parts = calendar.dateComponents([.minute, .second], from: date)
        return calendar.date(
            bySettingHour: baseHour,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0,
            of: date
        ) ?? date
    }
}

/// Pure placement rules for a day's presentations. No Core Data, so the whole
/// AM/PM gesture is testable without a store.
enum DayHalfPlanner {
    /// One presentation's place in a day: which record, and which half.
    struct Placement: Equatable, Sendable {
        let id: UUID
        var period: DayPeriod
    }

    /// The half a dropped presentation inherits.
    ///
    /// `periods` is the day's *other* presentations in order, and `index` is
    /// where the drop lands among them, so `index - 1` is the card the guide
    /// dropped under — that card's half is the answer, which is the whole
    /// gesture: drop a lesson beneath a morning lesson and it is a morning
    /// lesson.
    ///
    /// A drop at the very top has nothing above to copy, so it joins the run it
    /// landed in front of instead; that keeps the pill where the guide aimed it
    /// rather than opening a morning above an afternoon-only day. An empty day
    /// is a morning.
    static func inheritedPeriod(insertingAt index: Int, into periods: [DayPeriod]) -> DayPeriod {
        if index > 0, index - 1 < periods.count { return periods[index - 1] }
        return periods.first ?? .morning
    }

    /// The day reordered after one presentation changes halves: it leaves its
    /// own run and joins the end of the other one.
    ///
    /// The end, because "put this in the afternoon" says which half and not
    /// which slot — and landing last is the only position that does not push
    /// some other lesson down to make room.
    static func movingToEndOfHalf(
        _ movedID: UUID,
        to period: DayPeriod,
        in placements: [Placement]
    ) -> [Placement] {
        var remaining = placements.filter { $0.id != movedID }
        // Days are always morning-then-afternoon, so the slot after the last
        // card of this half is the end of the run. With no run to join, a
        // morning goes to the front and an afternoon to the back.
        let insertionIndex = remaining.lastIndex { $0.period == period }.map { $0 + 1 }
            ?? (period == .morning ? 0 : remaining.count)
        remaining.insert(Placement(id: movedID, period: period), at: insertionIndex)
        return remaining
    }

    /// Second-spaced times for a day's presentations, in list order, each
    /// counting from its own half's base hour.
    ///
    /// `spacingSeconds` must stay whole for the same reason
    /// `PlanningDropUtils.assignSequentialTimes` requires it: backups encode
    /// dates to whole-second precision, so sub-second offsets would collapse
    /// the order into ties across an export and restore.
    static func times(
        for placements: [Placement],
        on day: Date,
        using calendar: Calendar,
        spacingSeconds: Int
    ) -> [UUID: Date] {
        let startOfDay = calendar.startOfDay(for: day)
        var ranks: [DayPeriod: Int] = [:]
        var result: [UUID: Date] = [:]
        for placement in placements {
            let rank = ranks[placement.period, default: 0]
            ranks[placement.period] = rank + 1
            let base = calendar.date(
                byAdding: .hour,
                value: placement.period.baseHour,
                to: startOfDay
            ) ?? startOfDay
            result[placement.id] = calendar.date(
                byAdding: .second,
                value: rank * spacingSeconds,
                to: base
            ) ?? base
        }
        return result
    }
}
