import Foundation

// MARK: - Practice Stats

struct PracticeStats {
    var totalSessions: Int = 0
    var totalDuration: String?
    var topBehaviors: [String] = []
    var needsReteaching: Int = 0
    var upcomingCheckIns: Int = 0
}

struct PracticeStatsCalculator {
    /// Practice is a check-in now (`PracticeCheckIns`): the minutes are on the
    /// check-in and what was noticed is its note's tags. `scheduled` is the
    /// work's check-ins still to come. `today` is a parameter so tests can pin it.
    static func calculate(
        from practice: [CDWorkCheckIn], scheduled: [CDWorkCheckIn] = [], today: Date = Date()
    ) -> PracticeStats {
        var stats = PracticeStats()
        let tags = practice.map(\.noteTags)

        stats.totalSessions = practice.count
        stats.totalDuration = formatDuration(minutes: practice.compactMap(\.durationMinutesValue).reduce(0, +))
        stats.topBehaviors = topTags(tags, limit: 3)
        stats.needsReteaching = practice.filter { $0.practiceSignals.contains(.needsReteaching) }.count
        // Upcoming means today or later: a check-in date from last month is
        // history.
        let startOfToday = AppCalendar.startOfDay(today)
        stats.upcomingCheckIns = scheduled.filter { checkIn in
            checkIn.status == .scheduled
                && (checkIn.date.map { AppCalendar.startOfDay($0) >= startOfToday } ?? false)
        }.count
        return stats
    }

    private static func formatDuration(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%.1f hrs", Double(minutes) / 60.0)
    }

    private static func topTags(_ tags: [[String]], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for tag in tags.flatMap({ Array(Set($0)) }) {
            counts[tag, default: 0] += 1
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }
}
