// DayHalfPlanner.swift
// When a scheduled presentation happens: which half of the day it sits in,
// whether the guide gave it a start time, and how a day is numbered so both
// survive every reorder.
//
// Most presentations have no time — the guide plans an order, not a
// timetable — so `scheduledFor` carries that order as second-spaced offsets
// from a base hour: morning items count up from 9, afternoon items from 2.
// Some have a start time the guide set (the card's time chip, the lesson's
// sheet, or a tool's `time:`), and that lives in the same date. Nothing new is
// stored in either case: the Core Data model is CloudKit-mirrored and edited in
// place, so the two are told apart by how the date is written.
//
// How a stored moment reads (`moment(of:)`, plan "Lesson times on cards",
// decision 4):
//
//   midnight                                    → a morning slot (rows written
//                                                 before the halves existed);
//                                                 0:00:59 is a set midnight
//   base hour (9 or 14), minute 0, second 0–58  → a slot in that half; the
//                                                 second is its rank
//   base hour, minute 0, second 59              → a set time of exactly 9:00
//                                                 or 2:00 (the marker)
//   any other time, second 0                    → a set time
//   any other time, second ≠ 0                  → a slot in that half (an old
//                                                 value pushed one second below
//                                                 a timed lesson)
//
// Every write of a set time goes through `settingTime(hour:minute:on:)`, so a
// set time never carries stray seconds, and slot ranks stop at 58 so a slot
// can never be mistaken for the marker.
//
// Numbering per half rather than across the whole day is what keeps the two
// halves apart. Six morning lessons and one afternoon lesson are 9:00:00–9:00:05
// and 14:00:00, so no amount of reordering can walk the morning run into the
// afternoon. A set time is never renumbered: it decides its own place, first in
// its half in clock order (`LessonAssignmentOrdering`).

import Foundation

// `DayPeriod` itself is declared in Planning/PlanningModels.swift, with the
// label, colour and base hour the planning screens already used.
nonisolated extension DayPeriod {
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

    /// `date` moved into this half.
    ///
    /// An ordering slot keeps its rank: 9:00:05 is the sixth lesson of the
    /// morning, and flipping it to the afternoon makes it the sixth there
    /// (14:00:05), not flattened onto whatever is already at 2:00 sharp.
    ///
    /// A set time already in this half is left alone. One in the other half is
    /// removed, and the lesson takes the last slot of this half: 10:30 can't be
    /// an afternoon time, and carrying its minutes across used to turn it into
    /// 2:30, a time nobody set.
    func applied(to date: Date, using calendar: Calendar = AppCalendar.shared) -> Date {
        switch DayHalfPlanner.moment(of: date, using: calendar) {
        case .time:
            guard DayPeriod(scheduledFor: date, using: calendar) != self else { return date }
            return DayHalfPlanner.slot(DayHalfPlanner.lastSlotRank, in: self, on: date, using: calendar)
        case .half:
            let rank = min(calendar.component(.second, from: date), DayHalfPlanner.lastSlotRank)
            return DayHalfPlanner.slot(rank, in: self, on: date, using: calendar)
        }
    }
}

/// What a stored `scheduledFor` actually says about *when*.
///
/// The encoding above means a scheduled moment is one of two quite different
/// things, and a reader that prints it as a wall clock reports the wrong one:
/// every ordering slot comes back "09:00" or "14:00", which is a time nobody
/// set and which hides the real distinction — morning versus afternoon.
nonisolated enum ScheduledMoment: Equatable, Sendable {
    /// An ordering slot: the guide chose a half of the day, not a time.
    case half(DayPeriod)
    /// A time the guide actually set, from the time picker or a tool's `time:`.
    /// Print and compare its hour and minute only: an exact 9:00 or 2:00 is
    /// stored at second 59.
    case time(Date)
}

/// Pure placement rules for a day's presentations. No Core Data, so the whole
/// AM/PM gesture and every rule about set times is testable without a store.
nonisolated enum DayHalfPlanner {
    /// The highest second an ordering slot uses. Second 59 at a base hour is
    /// the marker for a set time of exactly that hour, so slots stop short of
    /// it; a half with more lessons than this shares the last rank, and the
    /// ordering's tie-breaks keep those few in a stable order.
    static let lastSlotRank = 58

    /// The second that marks a set time of exactly a base hour.
    private static let exactHourMarker = 59

    /// Reads a stored moment back as the thing it was written to mean (the
    /// table in the header).
    static func moment(
        of date: Date,
        using calendar: Calendar = AppCalendar.shared
    ) -> ScheduledMoment {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        if hour == 0, minute == 0 { return second == exactHourMarker ? .time(date) : .half(.morning) }
        if minute == 0, let period = DayPeriod.allCases.first(where: { $0.baseHour == hour }) {
            return second == exactHourMarker ? .time(date) : .half(period)
        }
        if second == 0 { return .time(date) }
        return .half(DayPeriod(scheduledFor: date, using: calendar))
    }

    /// Whether `date` is a time the guide set, rather than an ordering slot.
    static func isSetTime(_ date: Date?, using calendar: Calendar = AppCalendar.shared) -> Bool {
        keptTime(of: date, using: calendar) != nil
    }

    /// A set time as minutes after midnight (10:30 is 630), or nil for an
    /// ordering slot or no schedule at all. This is the form the time picker
    /// and the clash check work in: hour and minute, never seconds.
    static func setMinute(of date: Date?, using calendar: Calendar = AppCalendar.shared) -> Int? {
        guard let kept = keptTime(of: date, using: calendar) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: kept)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Setting and removing a time

    /// `day` at a time the guide set. The only way a set time is written: an
    /// exact base hour (9:00, 2:00) or midnight takes the marker second so it
    /// doesn't read back as an ordering slot, and every other time is on the
    /// minute.
    ///
    /// Set on the clock rather than added to midnight, which is off by an hour
    /// on the daylight-saving Sundays.
    static func settingTime(
        hour: Int,
        minute: Int,
        on day: Date,
        using calendar: Calendar = AppCalendar.shared
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let readsAsSlot = minute == 0 && (hour == 0 || DayPeriod.allCases.contains { $0.baseHour == hour })
        return calendar.date(
            bySettingHour: hour, minute: minute, second: readsAsSlot ? exactHourMarker : 0, of: startOfDay
        ) ?? startOfDay
    }

    /// `date` with its set time taken off: the lesson stays in the half it was
    /// in, at the last slot there, below the lessons already ordered by hand.
    /// The next reorder renumbers it. A slot comes back unchanged.
    static func removingTime(from date: Date, using calendar: Calendar = AppCalendar.shared) -> Date {
        guard case .time = moment(of: date, using: calendar) else { return date }
        return slot(lastSlotRank, in: DayPeriod(scheduledFor: date, using: calendar), on: date, using: calendar)
    }

    /// `date` moved to `day` at the same clock time, to the second, so a set
    /// time stays the same time (and an exact 9:00 keeps its marker). Set on
    /// the clock, so a daylight-saving Sunday doesn't shift it by an hour.
    static func rebasing(
        _ date: Date,
        onto day: Date,
        using calendar: Calendar = AppCalendar.shared
    ) -> Date {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(
            bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0, of: startOfDay
        ) ?? startOfDay
    }

    /// The ordering slot `rank` of `period` on `date`'s day.
    static func slot(
        _ rank: Int,
        in period: DayPeriod,
        on date: Date,
        using calendar: Calendar = AppCalendar.shared
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(
            bySettingHour: period.baseHour, minute: 0, second: min(max(rank, 0), lastSlotRank), of: startOfDay
        ) ?? startOfDay
    }

    // MARK: - Clashes

    /// The lessons of one day set for the same start time as another lesson
    /// that day, whoever the children are: the guide can only give one of
    /// them (decision 7). Lessons with no set time never clash here.
    static func sameTimeClashes(
        in scheduled: [UUID: Date],
        using calendar: Calendar = AppCalendar.shared
    ) -> Set<UUID> {
        var byMinute: [Int: [UUID]] = [:]
        for (id, date) in scheduled {
            guard let minute = setMinute(of: date, using: calendar) else { continue }
            byMinute[minute, default: []].append(id)
        }
        return byMinute.values.reduce(into: Set<UUID>()) { clashing, ids in
            if ids.count > 1 { clashing.formUnion(ids) }
        }
    }

    // MARK: - Placing a day

    /// One presentation's place in a day: which record, and which half.
    ///
    /// `keptTime` is a time the guide set (`moment(of:)` reads it as `.time`).
    /// Renumbering the day leaves it at that clock time, so a lesson set for
    /// 10:30 stays 10:30 when something else on the day is dragged, flipped or
    /// balanced, and when it is dropped on another day itself.
    struct Placement: Equatable, Sendable {
        let id: UUID
        var period: DayPeriod
        var keptTime: Date?

        init(id: UUID, period: DayPeriod, keptTime: Date? = nil) {
            self.id = id
            self.period = period
            self.keptTime = keptTime
        }
    }

    /// The stored time a card keeps through a renumbering: its own, when it is
    /// a time the guide set rather than an ordering slot. Nil for a slot, or
    /// for no schedule at all.
    static func keptTime(of scheduledFor: Date?, using calendar: Calendar = AppCalendar.shared) -> Date? {
        guard let scheduledFor, case .time = moment(of: scheduledFor, using: calendar) else { return nil }
        return scheduledFor
    }

    /// The half a dropped presentation with no set time inherits.
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

    /// The day in its new order after a drop, each card carrying its half.
    ///
    /// `ids` is the whole day with the dropped cards already in place, together
    /// (`WeekDayColumnDropDelegate.ordering`), and `scheduledFor` is each card's
    /// stored moment before the drop — on another day, for a card dragged here.
    ///
    /// Every card already on the day keeps its own half and any time set on
    /// it. A dropped card with a set time keeps that time and so its own half,
    /// wherever in the column it landed: a drag never changes a time
    /// (decision 5). A dropped card without one takes the half of the card it
    /// landed under, which is the whole AM/PM gesture — and also what keeps a
    /// reorder honest, since dragging a morning lesson below the afternoon run
    /// makes it an afternoon lesson rather than leaving it stranded.
    static func placementsAfterDrop(
        ordering ids: [UUID],
        dropped: Set<UUID>,
        scheduledFor: [UUID: Date],
        using calendar: Calendar = AppCalendar.shared
    ) -> [Placement] {
        func half(_ itemID: UUID) -> DayPeriod {
            guard let scheduled = scheduledFor[itemID] else { return .morning }
            return DayPeriod(scheduledFor: scheduled, using: calendar)
        }
        func kept(_ itemID: UUID) -> Date? {
            keptTime(of: scheduledFor[itemID], using: calendar)
        }

        // The dropped cards sit together, so the first of them is where the
        // drop landed among the others, and the untimed ones take that half.
        let insertionIndex = ids.firstIndex { dropped.contains($0) } ?? ids.count
        let inherited = inheritedPeriod(
            insertingAt: insertionIndex,
            into: ids.filter { !dropped.contains($0) }.map(half)
        )
        return ids.map { itemID in
            if let time = kept(itemID) {
                return Placement(id: itemID, period: half(itemID), keptTime: time)
            }
            return Placement(id: itemID, period: dropped.contains(itemID) ? inherited : half(itemID))
        }
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

    /// Second-spaced times for a day's presentations, in list order, each slot
    /// counting from its own half's base hour.
    ///
    /// A placement carrying a `keptTime` comes back at that clock time on
    /// `day` and takes no slot. Slots always count from the base hour — a set
    /// time sorts first in its half on its own (`LessonAssignmentOrdering`), so
    /// a slot no longer has to "count on" past one to draw below it — and stop
    /// at `lastSlotRank`.
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
        var ranks: [DayPeriod: Int] = [:]
        var result: [UUID: Date] = [:]
        for placement in placements {
            if let kept = placement.keptTime {
                result[placement.id] = rebasing(kept, onto: day, using: calendar)
                continue
            }
            let rank = ranks[placement.period, default: 0]
            ranks[placement.period] = rank + 1
            result[placement.id] = slot(rank * spacingSeconds, in: placement.period, on: day, using: calendar)
        }
        return result
    }
}
