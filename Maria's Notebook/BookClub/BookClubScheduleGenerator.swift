import Foundation

/// Pure schedule generation for book club sessions. No Core Data writes.
enum BookClubScheduleGenerator {

    /// One generated meeting before persistence.
    struct GeneratedMeeting: Hashable, Sendable {
        let ordinal: Int
        let date: Date
        let readingLabel: String
        let leaderStudentID: UUID?
    }

    /// Generates a schedule by pairing reading items with dates.
    /// - Parameters:
    ///   - startDate: Date of the first meeting. Used as-is when its weekday matches the cadence.
    ///                For weekly/biweekly, the weekday is taken from `startDate`. For `.custom`,
    ///                the first matching date on or after `startDate` is used.
    ///   - cadence: How to space meetings.
    ///   - readingItems: Reading items from the packet, in display order.
    ///   - roster: Student UUIDs in roster order. Used only when `rotateLeader` is true.
    ///   - rotateLeader: If true, leader rotates through the roster (`ordinal-1 % roster.count`).
    ///   - calendar: Calendar used for date arithmetic. Defaults to current.
    static func generate(
        startDate: Date,
        cadence: BookClubCadence,
        readingItems: [BookClubReadingItem],
        roster: [UUID],
        rotateLeader: Bool,
        calendar: Calendar = .current
    ) -> [GeneratedMeeting] {
        guard !readingItems.isEmpty else { return [] }

        let dates: [Date]
        switch cadence {
        case .weekly(let weekday):
            let first = firstDate(onOrAfter: startDate, weekday: weekday, calendar: calendar)
            dates = (0..<readingItems.count).compactMap { offset in
                calendar.date(byAdding: .day, value: offset * 7, to: first)
            }
        case .biweekly(let weekday):
            let first = firstDate(onOrAfter: startDate, weekday: weekday, calendar: calendar)
            dates = (0..<readingItems.count).compactMap { offset in
                calendar.date(byAdding: .day, value: offset * 14, to: first)
            }
        case .custom(let weekdayMask):
            dates = customDates(
                startingOnOrAfter: startDate,
                weekdayMask: weekdayMask,
                count: readingItems.count,
                calendar: calendar
            )
        }

        let sortedItems = readingItems.sorted { $0.ordinal < $1.ordinal }
        return zip(sortedItems, dates).enumerated().map { index, pair in
            let (item, date) = pair
            let ordinal = index + 1
            let leader: UUID?
            if rotateLeader, !roster.isEmpty {
                leader = roster[(ordinal - 1) % roster.count]
            } else {
                leader = nil
            }
            return GeneratedMeeting(
                ordinal: ordinal,
                date: date,
                readingLabel: item.label,
                leaderStudentID: leader
            )
        }
    }

    /// Returns the next date whose weekday matches, walking forward from `date`.
    /// `weekday` uses Foundation's convention: 1 = Sunday, …, 7 = Saturday.
    private static func firstDate(onOrAfter date: Date, weekday: Int, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let current = calendar.component(.weekday, from: startOfDay)
        let delta = (weekday - current + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: startOfDay) ?? startOfDay
    }

    /// Walks forward day-by-day picking dates whose weekday bit is set in `weekdayMask`.
    /// Bit positions follow the `CDPrepChecklist.weekdayMask` convention:
    /// bit 1 = Sunday, bit 2 = Monday, …, bit 7 = Saturday (1-indexed shifts).
    private static func customDates(
        startingOnOrAfter date: Date,
        weekdayMask: Int64,
        count: Int,
        calendar: Calendar
    ) -> [Date] {
        guard weekdayMask != 0, count > 0 else { return [] }
        var results: [Date] = []
        var cursor = calendar.startOfDay(for: date)
        let maxIterations = count * 14 + 14
        var iteration = 0
        while results.count < count, iteration < maxIterations {
            let weekday = calendar.component(.weekday, from: cursor)
            if isWeekdaySet(weekday, in: weekdayMask) {
                results.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            iteration += 1
        }
        return results
    }

    /// `weekday` is 1...7 (Sun...Sat). Bit position is `1 << weekday`.
    private static func isWeekdaySet(_ weekday: Int, in mask: Int64) -> Bool {
        guard weekday >= 1, weekday <= 7 else { return false }
        return (mask & (Int64(1) << weekday)) != 0
    }
}
