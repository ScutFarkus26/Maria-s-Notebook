// SchoolYearScoping.swift
// In-memory helpers for scoping already-fetched model objects to a school-year range.
// Used where a view already holds a small collection (e.g. the student roster) and an
// in-memory filter is simpler and cheaper than a re-fetch.

import Foundation
import CoreData

nonisolated extension CDStudent {
    /// True if this student's enrollment overlaps `range` (i.e. they were active during it).
    /// Students with no start date are treated as always active (fail-open).
    func isActive(in range: DateRange) -> Bool {
        let startedOK = dateStarted.map { $0 < range.end } ?? true
        let withdrawnOK = dateWithdrawn.map { $0 >= range.start } ?? true
        return startedOK && withdrawnOK
    }
}

extension Sequence where Element == CDStudent {
    /// Roster for history views (reports, logs): students active during `range`,
    /// so former students still appear in the periods they were part of the class.
    /// Contrast with `filterEnrolled()`, which is for operational "today" views.
    func filterActive(in range: DateRange) -> [CDStudent] {
        filter { $0.isActive(in: range) }
    }
}

nonisolated extension CDProject {
    /// True if this project's activity window (creation through its last session or edit)
    /// overlaps `range`. Projects with no creation date fail open.
    func overlaps(_ range: DateRange) -> Bool {
        guard let created = createdAt else { return true }
        if created >= range.end { return false }
        let lastSession = ((sessions?.allObjects as? [CDProjectSession]) ?? [])
            .compactMap(\.meetingDate).max()
        let lastActivity = max(lastSession ?? created, modifiedAt ?? created, created)
        return lastActivity >= range.start
    }
}
