import Foundation

/// Remembers, on this device, the days arrival was closed on, so the Late
/// phase survives a relaunch mid-morning. Each day keeps its own: closing
/// arrival on another day (or reopening it there) leaves today's alone, so
/// a late child is still tardy after a look at yesterday.
///
/// Closing arrival on one device closes it on all of them
/// (`isLate(on:closedAnywhere:)`): another device sees Close Arrival's
/// automatic absences on the records, and a child who arrives after it is
/// tardy there too, not present. Reopening arrival here is remembered as
/// well, so a device can still go back to Arrival on purpose while those
/// absences stand.
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
    /// The most recent days kept; older ones are forgotten.
    static let dayLimit = 31

    /// Whether arrival was closed on `day` on this device.
    static func isLate(on day: Date, defaults: UserDefaults = .standard) -> Bool {
        lateDays(defaults).contains { Calendar.current.isDate($0, inSameDayAs: day) }
    }

    /// Whether `day` is in Late as this device sees it: arrival closed here,
    /// or closed anywhere (`closedAnywhere`: Close Arrival's automatic
    /// absence on a record that day, `CDAttendanceStore.arrivalClosed`)
    /// unless it was reopened here since. `closedAnywhere` is read only when
    /// this device hasn't closed the day itself.
    static func isLate(
        on day: Date, closedAnywhere: @autoclosure () -> Bool, defaults: UserDefaults = .standard
    ) -> Bool {
        if isLate(on: day, defaults: defaults) { return true }
        let reopened = days(reopenedKey, defaults).contains { Calendar.current.isDate($0, inSameDayAs: day) }
        return !reopened && closedAnywhere()
    }

    /// Closes arrival on `day` here, or forgets that it did. Either way a
    /// reopen remembered for the day goes: the day follows the records again.
    static func setLate(_ late: Bool, on day: Date, defaults: UserDefaults = .standard) {
        save(lateDays(defaults), with: day, included: late, key: key, defaults: defaults)
        defaults.removeObject(forKey: singleDayKey)
        save(days(reopenedKey, defaults), with: day, included: false, key: reopenedKey, defaults: defaults)
    }

    /// Back to Arrival on `day` here, on purpose: it stays open on this
    /// device even where another device's Close Arrival shows on the records.
    static func reopen(on day: Date, defaults: UserDefaults = .standard) {
        setLate(false, on: day, defaults: defaults)
        save(days(reopenedKey, defaults), with: day, included: true, key: reopenedKey, defaults: defaults)
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: singleDayKey)
        defaults.removeObject(forKey: reopenedKey)
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
}
