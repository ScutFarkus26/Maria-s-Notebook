// AttendanceInsightsService+Sidebar.swift
// The Mac insights sidebar's four aggregations from one attendance read.

import Foundation
import CoreData
import OSLog

extension AttendanceInsightsService {
    /// The stored bounds a range is queried with: both ends snapped to midnight,
    /// so the upper bound admits only records stamped exactly at its midnight.
    fileprivate static func storedBounds(of range: ClosedRange<Date>) -> (start: Date, end: Date) {
        (AppCalendar.startOfDay(range.lowerBound), AppCalendar.startOfDay(range.upperBound))
    }

    /// Records in any of `ranges` (same bounds as `fetchRecords`), in one read and
    /// *not* deduplicated — dedup belongs to each range's own slice, because a
    /// student-day's duplicates can straddle one range's edge.
    static func fetchRawRecords(
        in ranges: [ClosedRange<Date>],
        context: NSManagedObjectContext,
        fetchLabel: String
    ) -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        let clauses = ranges.map { range -> NSPredicate in
            let bounds = storedBounds(of: range)
            return NSPredicate(format: "date >= %@ AND date <= %@", bounds.start as NSDate, bounds.end as NSDate)
        }
        request.predicate = clauses.count == 1
            ? clauses[0]
            : NSCompoundPredicate(orPredicateWithSubpredicates: clauses)
        do {
            return try context.fetch(request)
        } catch {
            let label = fetchLabel
            let message = error.localizedDescription
            logger.warning("\(label, privacy: .public) fetch failed: \(message, privacy: .public)")
            return []
        }
    }
}

/// Slices one multi-range read into what `fetchRecords(in:)` returns for each
/// range: the same bounds test in memory, then the same per-student-day dedup
/// over the slice, in the order the read returned the rows.
struct AttendanceRecordPool {
    let raw: [CDAttendanceRecord]

    func records(in range: ClosedRange<Date>) -> [CDAttendanceRecord] {
        let start = AppCalendar.startOfDay(range.lowerBound)
        let end = AppCalendar.startOfDay(range.upperBound)
        return raw.filter { record in
            guard let date = record.date else { return false }
            return date >= start && date <= end
        }.deduplicatedPerStudentDay()
    }
}

// MARK: - Sidebar (one read)

/// Everything the Mac insights sidebar shows for one timeframe.
struct AttendanceSidebarInsights {
    let summary: AttendanceClassSummary
    let priorSummary: AttendanceClassSummary
    let watchList: [AttendanceWatchListEntry]
    let recentActivity: [AttendanceRecentActivityEntry]
}

extension AttendanceInsightsService {
    /// The sidebar's four aggregations from a single fetch over the union of
    /// the ranges they need (it was five fetches per attendance tap, the
    /// current range read twice). Each aggregation sees exactly the records
    /// its own fetch returned.
    static func sidebarInsights(
        range: ClosedRange<Date>,
        priorRange: ClosedRange<Date>,
        students: [CDStudent],
        context: NSManagedObjectContext,
        watchListLimit: Int = 5,
        recentDayCount: Int = 5
    ) -> AttendanceSidebarInsights {
        let end = AppCalendar.startOfDay(range.upperBound)
        let patternDays = patternDayRange(endingAt: end, count: 10, context: context)
        let recentDays = recentSchoolDays(endingAt: range.upperBound, count: recentDayCount, context: context)

        var ranges = [range, priorRange]
        if let first = patternDays.first, let last = patternDays.last { ranges.append(first...last) }
        if let earliest = recentDays.last, let latest = recentDays.first { ranges.append(earliest...latest) }
        let raw = fetchRawRecords(in: ranges, context: context, fetchLabel: "sidebarInsights")
        let pool = AttendanceRecordPool(raw: raw)

        let current = pool.records(in: range)
        let patternRecords = patternDays.first.flatMap { first in
            patternDays.last.map { pool.records(in: first...$0) }
        } ?? []
        let recentRecords = recentDays.last.flatMap { earliest in
            recentDays.first.map { pool.records(in: earliest...$0) }
        } ?? []

        return AttendanceSidebarInsights(
            summary: classSummary(records: current, students: students),
            priorSummary: classSummary(records: pool.records(in: priorRange), students: students),
            watchList: watchList(
                records: current, students: students,
                patternDays: patternDays, patternRecords: patternRecords, limit: watchListLimit
            ),
            recentActivity: recentActivity(schoolDays: recentDays, records: recentRecords, students: students)
        )
    }
}
