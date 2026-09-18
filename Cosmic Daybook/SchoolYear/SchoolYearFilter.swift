// SchoolYearFilter.swift
// NSPredicate factories that scope Core Data fetches to a school-year `DateRange`.
//
// One source of truth for every fetch site. Each factory returns `nil` when `range` is nil
// (the `.allTime` lens) so callers can AND it into an existing predicate and cleanly
// short-circuit. Undated records fail *open* (are included) by default so nothing silently
// disappears when the lens is on — see Documentation/Implementation/SCHOOL_YEAR_SEPARATION.md.

import Foundation
import CoreData

enum SchoolYearFilter {
    /// A point-in-time record belongs to the range if its governing date ∈ [start, end).
    /// - Parameter includeUndated: when true (default), records with a nil date are included.
    static func pointInTime(
        _ keyPath: String,
        in range: DateRange?,
        includeUndated: Bool = true
    ) -> NSPredicate? {
        guard let range else { return nil }
        let inRange = NSPredicate(
            format: "(%K >= %@) AND (%K < %@)",
            keyPath, range.start as NSDate,
            keyPath, range.end as NSDate
        )
        guard includeUndated else { return inRange }
        let undated = NSPredicate(format: "%K == nil", keyPath)
        return NSCompoundPredicate(orPredicateWithSubpredicates: [inRange, undated])
    }

    /// A span record (e.g. WorkModel) belongs to the range if its active interval *overlaps*
    /// [start, end): created before the range ends, and either completed on/after the range
    /// starts, or still open and last touched on/after it. Open work with no touch date counts
    /// as active. This is the "show while active" rule.
    static func span(
        createdAt: String,
        completedAt: String,
        touchedAt: String,
        in range: DateRange?,
        includeUndated: Bool = true
    ) -> NSPredicate? {
        guard let range else { return nil }
        let core = NSPredicate(
            format: "(%K < %@) AND ((%K >= %@) OR (%K == nil AND (%K == nil OR %K >= %@)))",
            createdAt, range.end as NSDate,
            completedAt, range.start as NSDate,
            completedAt, touchedAt, touchedAt, range.start as NSDate
        )
        guard includeUndated else { return core }
        let undated = NSPredicate(format: "%K == nil", createdAt)
        return NSCompoundPredicate(orPredicateWithSubpredicates: [core, undated])
    }

    /// A student is "active" in the range if enrolled before it ends and not withdrawn before
    /// it starts. Students with no start date are always included (fail-open).
    static func roster(
        in range: DateRange?,
        startedKey: String = "dateStarted",
        withdrawnKey: String = "dateWithdrawn"
    ) -> NSPredicate? {
        guard let range else { return nil }
        return NSPredicate(
            format: "(%K == nil OR %K < %@) AND (%K == nil OR %K >= %@)",
            startedKey, startedKey, range.end as NSDate,
            withdrawnKey, withdrawnKey, range.start as NSDate
        )
    }

    /// ANDs an optional year predicate onto an existing one, dropping nils. Returns nil only
    /// when both are nil (no filtering at all).
    static func combine(_ base: NSPredicate?, _ year: NSPredicate?) -> NSPredicate? {
        switch (base, year) {
        case (nil, nil): return nil
        case let (base?, nil): return base
        case let (nil, year?): return year
        case let (base?, year?):
            return NSCompoundPredicate(andPredicateWithSubpredicates: [base, year])
        }
    }
}
