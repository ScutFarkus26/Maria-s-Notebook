// SchoolYearScoping.swift
// In-memory helpers for scoping already-fetched model objects to a school-year range.
// Used where a view already holds a small collection (e.g. the student roster) and an
// in-memory filter is simpler and cheaper than a re-fetch.

import Foundation
import CoreData

nonisolated extension CDStudent {
    /// True if this student was in the class at some point during `range`
    /// (`isInClass(from:until:)`, the one rule, domain logic review R7). A
    /// student with no start date counts from the beginning; a departed one
    /// with no last day is out, as she is on the attendance roll.
    func isActive(in range: DateRange) -> Bool {
        isInClass(during: range)
    }

    /// Whether she was in the class at some point during `range`.
    func isInClass(during range: DateRange, calendar: Calendar = AppCalendar.shared) -> Bool {
        isInClass(from: range.start, until: range.end, calendar: calendar)
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
