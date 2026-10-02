// AttendanceInsightsService+Sidebar.swift
// The Mac insights sidebar's aggregations from one attendance read.

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
    /// Children with absences or late arrivals, siblings gathered.
    let patterns: [AttendancePattern]
}

extension AttendanceInsightsService {
    /// The sidebar's aggregations from a single fetch over the union of the
    /// ranges they need (it was five fetches per attendance tap, the current
    /// range read twice). Each aggregation sees exactly the records its own
    /// fetch returned.
    static func sidebarInsights(
        range: ClosedRange<Date>,
        priorRange: ClosedRange<Date>,
        students: [CDStudent],
        context: NSManagedObjectContext,
        patternLimit: Int = 5
    ) -> AttendanceSidebarInsights {
        let end = AppCalendar.startOfDay(range.upperBound)
        let patternDays = patternDayRange(endingAt: end, count: 10, context: context)

        var ranges = [range, priorRange]
        if let first = patternDays.first, let last = patternDays.last { ranges.append(first...last) }
        let raw = fetchRawRecords(in: ranges, context: context, fetchLabel: "sidebarInsights")
        let pool = AttendanceRecordPool(raw: raw)

        let current = pool.records(in: range)
        let patternRecords = patternDays.first.flatMap { first in
            patternDays.last.map { pool.records(in: first...$0) }
        } ?? []

        // Every child on the list, so a family's whole count is known
        // before the list is cut to `patternLimit`.
        let everyone = watchList(
            records: current, students: students,
            patternDays: patternDays, patternRecords: patternRecords, limit: .max
        )
        let keys = familyKeys(for: students, context: context)
        let lastNames = Dictionary(
            students.compactMap { student in student.id.map { ($0, student.lastName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return AttendanceSidebarInsights(
            summary: classSummary(records: current, students: students),
            priorSummary: classSummary(records: pool.records(in: priorRange), students: students),
            patterns: patterns(
                everyone, familyKey: { keys[$0] }, familyName: { lastNames[$0] ?? "" }, limit: patternLimit
            )
        )
    }
}
