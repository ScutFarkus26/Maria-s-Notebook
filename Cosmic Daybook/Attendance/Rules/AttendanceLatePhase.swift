import Foundation
import CoreData

/// Remembers, on this device, the days arrival was closed on, so the Late
/// phase survives a relaunch mid-morning. Each day keeps its own: closing
/// arrival on another day (or reopening it there) leaves today's alone, so
/// a late child is still tardy after a look at yesterday.
///
/// Closing arrival on one device closes it on all of them
/// (`isLate(on:closedAnywhere:)`): another device sees Close Arrival's
/// automatic absences on the records, and a child who arrives after it is
/// tardy there too, not present. Those absences don't last (a late child is
/// marked Late, an absent one given a reason), so each device also remembers
/// the children the close took in (`closedAnywhere(on:records:)`): everyone
/// it ever saw carrying the absence, and everyone it saw marked Late at or
/// after the close's time, since those were closed out and came in later.
/// The day stays closed until every one of them is unmarked again, which is
/// what an Undo of the close does, here or on another device, or marked
/// present once arrival went on after it. Every device keeps the same kind
/// of memory, so a phone that looks in between the changes reads the day as
/// the device that closed it does (review of the 2026-10-20 fixes, (a) 2).
/// On a phone that hadn't closed arrival, Late used to slip back to Arrival
/// once the absences were resolved, and a late child was marked present; on
/// one that had, another phone's Undo left it in Late with everyone
/// unmarked (bug hunt 2026-10-20, #2 and #5). Reopening arrival here is
/// remembered as well, so a device can still go back to Arrival on purpose,
/// and back to Late from there.
///
/// Shared with the Daybook Assistant. The keys keep their "Assistant." names:
/// each app has its own defaults, and renaming them would drop a Late phase
/// the Assistant closed before it updated.
@MainActor
enum AttendanceLatePhase {
    private static let key = "Assistant.latePhaseDays"
    /// Before each day kept its own, one day was remembered here.
    private static let singleDayKey = "Assistant.latePhaseDay"
    /// The days arrival was reopened on here, after closing somewhere.
    private static let reopenedKey = "Assistant.arrivalReopenedDays"
    /// The children Close Arrival took in on each day, as this device saw
    /// them (`closedAnywhere(on:records:)`): student ids by `yyyy-MM-dd`.
    private static let seenClosedKey = "Assistant.arrivalSeenClosed"
    /// When arrival closed on each day, as this device saw it: the earliest
    /// mark time of the automatic absences it saw, by `yyyy-MM-dd`.
    private static let closedAtKey = "Assistant.arrivalClosedAt"
    /// The most recent days kept; older ones are forgotten.
    static let dayLimit = 31

    /// Whether arrival was closed on `day` on this device.
    static func isLate(on day: Date, defaults: UserDefaults = .standard) -> Bool {
        lateDays(defaults).contains { Calendar.current.isDate($0, inSameDayAs: day) }
    }

    /// Whether `day` is in Late as this device sees it: arrival closed here,
    /// or closed anywhere (`closedAnywhere`, as `CDAttendanceStore.arrivalClosed`
    /// or `closedAnywhere(on:records:)` reads it) unless it was reopened here
    /// since. `closedAnywhere` is read first, every time: reading the records
    /// forgets a close here whose children another device's Undo put back.
    static func isLate(
        on day: Date, closedAnywhere: @autoclosure () -> Bool, defaults: UserDefaults = .standard
    ) -> Bool {
        let anywhere = closedAnywhere()
        if isLate(on: day, defaults: defaults) { return true }
        let reopened = days(reopenedKey, defaults).contains { Calendar.current.isDate($0, inSameDayAs: day) }
        return !reopened && anywhere
    }

    /// Whether arrival reads as closed on `day` from that day's `records`
    /// (every copy, as fetched): Close Arrival's automatic absence stands on
    /// one, or this device saw the day closed and not every child the close
    /// took in reads as undone (`readsUndone`). Resolving them (Late, a
    /// reason) or clearing some of them keeps the day closed; an Undo of the
    /// close, which puts exactly those children back to unmarked, forgets it,
    /// a close made here included, so the day follows the records again. So
    /// does an Undo this device only sees after arrival went on (one of them
    /// marked present by then). A child added to the roll since doesn't
    /// count either way.
    ///
    /// Remembers, on every read, the union of the children it has seen
    /// carrying the absence (the device that closed: everyone its close
    /// marked) and of those it sees marked Late at or after the close's time,
    /// the earliest automatic absence it has seen. A child marked Late from
    /// the menu before the close wasn't closed out, so isn't remembered, and
    /// doesn't keep the day closed after an Undo. Observers used to remember
    /// only who still carried the absence when they last looked, so clearing
    /// the last one read as an Undo there and not on the device that closed
    /// (review of the 2026-10-20 fixes, (a) 2). A day with no records at all
    /// (a store still downloading) says nothing about an Undo, so what was
    /// seen stands.
    @discardableResult
    static func closedAnywhere(
        on day: Date, records: [CDAttendanceRecord], defaults: UserDefaults = .standard
    ) -> Bool {
        let id = dayKey(day)
        var seen = seenClosed(defaults)
        var closedAt = closeTimes(defaults)
        let remembered = Set(seen[id] ?? [])
        let automatic = records.filter(AttendanceDeduplication.isAutomaticAbsence)
        let shown = Dictionary(
            records.deduplicatedPerStudentDay().map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var current = remembered.union(automatic.map(\.studentID))
        let closeTime = ([closedAt[id]] + automatic.map(\.markedAt)).compactMap { $0 }.min()
        if !current.isEmpty, let closeTime {
            current.formUnion(shown.values.filter { cameInAfter(closeTime, $0) }.map(\.studentID))
        }
        if current != remembered {
            seen[id] = current.sorted()
            save(seen, defaults)
        }
        if !current.isEmpty, let closeTime, closedAt[id] != closeTime {
            closedAt[id] = closeTime
            save(closedAt, defaults)
        }
        if !automatic.isEmpty { return true }
        guard !current.isEmpty else { return false }
        guard !records.isEmpty else { return true }
        let undone = current.allSatisfy { child in shown[child].map(readsUndone) ?? true }
        guard undone else { return true }
        setLate(false, on: day, defaults: defaults)
        return false
    }

    /// Whether `record` shows a child marked Late (or gone home after
    /// arriving late) at or after `closeTime`: closed out, then came in.
    private static func cameInAfter(_ closeTime: Date, _ record: CDAttendanceRecord) -> Bool {
        guard record.cameLate, let markedAt = record.markedAt else { return false }
        return markedAt >= closeTime
    }

    /// Whether a child who carried Close Arrival's absence reads as put back
    /// by an Undo: unmarked, or present. While arrival is closed, such a
    /// child who comes in is marked Late, never Present, so present means the
    /// close was undone and arrival went on. A device that missed the moment
    /// in between (another phone's Undo, then a present mark, in one import)
    /// read the day as closed, and the guide's ParentLocker backstop could
    /// send the class during arrival (review of the 2026-10-20 fixes).
    private static func readsUndone(_ record: CDAttendanceRecord) -> Bool {
        !AttendanceDeduplication.isMarked(record) || record.status == .present
    }

    /// Closes arrival on `day` here, or forgets that it did. Either way a
    /// reopen remembered for the day goes: the day follows the records again.
    /// Forgetting (an Undo of the close) also forgets the children this
    /// device saw the close take in, so the next look at the records starts
    /// afresh; closing keeps them, and adds the ones this close marks.
    static func setLate(_ late: Bool, on day: Date, defaults: UserDefaults = .standard) {
        save(lateDays(defaults), with: day, included: late, key: key, defaults: defaults)
        defaults.removeObject(forKey: singleDayKey)
        save(days(reopenedKey, defaults), with: day, included: false, key: reopenedKey, defaults: defaults)
        if !late { forgetSeenClosed(on: day, defaults: defaults) }
    }

    /// Back to Arrival on `day` here, on purpose: it stays open on this
    /// device even where another device's Close Arrival shows on the records.
    /// The children the close took in are kept, so the day still reads as
    /// closed by them and the bar offers the way back to Late; a Reopen used
    /// to forget them, and with every one of them resolved there was no way
    /// back (review of the 2026-10-20 fixes, (a) 3).
    static func reopen(on day: Date, defaults: UserDefaults = .standard) {
        save(lateDays(defaults), with: day, included: false, key: key, defaults: defaults)
        defaults.removeObject(forKey: singleDayKey)
        save(days(reopenedKey, defaults), with: day, included: true, key: reopenedKey, defaults: defaults)
    }

    /// Forgets every day: leaving the class, or the Sample Class.
    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: singleDayKey)
        defaults.removeObject(forKey: reopenedKey)
        defaults.removeObject(forKey: seenClosedKey)
        defaults.removeObject(forKey: closedAtKey)
    }

    private static func lateDays(_ defaults: UserDefaults) -> [Date] {
        var days = days(key, defaults)
        if let single = defaults.object(forKey: singleDayKey) as? Date { days.append(single) }
        return days
    }

    private static func days(_ key: String, _ defaults: UserDefaults) -> [Date] {
        defaults.array(forKey: key) as? [Date] ?? []
    }

    /// Writes `days` back under `key` with `day` in or out, keeping the most
    /// recent `dayLimit`.
    private static func save(
        _ days: [Date], with day: Date, included: Bool, key: String, defaults: UserDefaults
    ) {
        var days = days.filter { !Calendar.current.isDate($0, inSameDayAs: day) }
        if included { days.append(Calendar.current.startOfDay(for: day)) }
        defaults.set(Array(days.sorted().suffix(dayLimit)), forKey: key)
    }

    // MARK: - Seen closed

    /// `day` as `yyyy-MM-dd` in this device's calendar, which sorts by date.
    private static func dayKey(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func seenClosed(_ defaults: UserDefaults) -> [String: [String]] {
        defaults.dictionary(forKey: seenClosedKey) as? [String: [String]] ?? [:]
    }

    private static func closeTimes(_ defaults: UserDefaults) -> [String: Date] {
        defaults.dictionary(forKey: closedAtKey) as? [String: Date] ?? [:]
    }

    /// Forgets the children and the close time this device saw for `day`.
    private static func forgetSeenClosed(on day: Date, defaults: UserDefaults) {
        let id = dayKey(day)
        var seen = seenClosed(defaults)
        if seen.removeValue(forKey: id) != nil { save(seen, defaults) }
        var closedAt = closeTimes(defaults)
        if closedAt.removeValue(forKey: id) != nil { save(closedAt, defaults) }
    }

    /// Writes `seen` back, keeping the most recent `dayLimit` days.
    private static func save(_ seen: [String: [String]], _ defaults: UserDefaults) {
        defaults.set(recent(seen), forKey: seenClosedKey)
    }

    /// Writes `closedAt` back, keeping the most recent `dayLimit` days.
    private static func save(_ closedAt: [String: Date], _ defaults: UserDefaults) {
        defaults.set(recent(closedAt), forKey: closedAtKey)
    }

    /// `byDay`'s most recent `dayLimit` days.
    private static func recent<Value>(_ byDay: [String: Value]) -> [String: Value] {
        let kept = Set(byDay.keys.sorted().suffix(dayLimit))
        return byDay.filter { kept.contains($0.key) }
    }
}
