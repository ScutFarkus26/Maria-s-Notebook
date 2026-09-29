import Foundation

/// Remembers, on this device, the days arrival was closed on, so the Late
/// phase survives a relaunch mid-morning. Each day keeps its own: closing
/// arrival on another day (or reopening it there) leaves today's alone, so
/// a late child is still tardy after a look at yesterday.
@MainActor
enum AssistantLatePhase {
    private static let key = "Assistant.latePhaseDays"
    /// Before each day kept its own, one day was remembered here.
    private static let singleDayKey = "Assistant.latePhaseDay"
    /// The most recent days kept; older ones are forgotten.
    static let dayLimit = 31

    static func isLate(on day: Date, defaults: UserDefaults = .standard) -> Bool {
        lateDays(defaults).contains { Calendar.current.isDate($0, inSameDayAs: day) }
    }

    static func setLate(_ late: Bool, on day: Date, defaults: UserDefaults = .standard) {
        var days = lateDays(defaults).filter { !Calendar.current.isDate($0, inSameDayAs: day) }
        if late { days.append(Calendar.current.startOfDay(for: day)) }
        days = Array(days.sorted().suffix(dayLimit))
        defaults.set(days, forKey: key)
        defaults.removeObject(forKey: singleDayKey)
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: singleDayKey)
    }

    private static func lateDays(_ defaults: UserDefaults) -> [Date] {
        var days = defaults.array(forKey: key) as? [Date] ?? []
        if let single = defaults.object(forKey: singleDayKey) as? Date { days.append(single) }
        return days
    }
}
