//
//  SchoolCalendarService+ExplicitSet.swift
//  Cosmic Daybook
//
//  The explicit "make this date a school day / a no-school day" write, the
//  idempotent counterpart to `toggleNonSchoolDay` for callers that say what
//  they want rather than flip what is there (the MCP tools).
//

import CoreData
import Foundation

extension SchoolCalendarService {
    // MARK: - Explicit Set

    /// What `setSchoolDay` did to a date.
    public enum SchoolDayChange: Equatable, Sendable {
        /// The date was already in the requested state.
        case unchanged
        /// The date was already a no-school day; only its reason was updated.
        case reasonUpdated
        /// The date is now a no-school day.
        case markedNonSchool
        /// The date is now a school day.
        case markedSchool
    }

    /// Sets a date's state explicitly — the idempotent counterpart to
    /// `toggleNonSchoolDay`, for callers (the MCP tools) that say what they want
    /// rather than flip what is there. Applies the same records the grid's tap
    /// does, under `SchoolDayChecker`'s precedence:
    /// - a weekday out of session gets a `NonSchoolDay` (with `reason`);
    /// - a weekday in session loses any `NonSchoolDay`;
    /// - a weekend in session gets a `SchoolDayOverride`, and loses any
    ///   `NonSchoolDay` that would beat the override;
    /// - a weekend out of session loses both.
    /// The caller saves. Every change is announced so caches drop.
    @discardableResult
    public func setSchoolDay(
        _ date: Date, inSession: Bool, reason: String? = nil,
        using context: NSManagedObjectContext
    ) throws -> SchoolDayChange {
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)

        let nonSchoolFetch = NSFetchRequest<CDNonSchoolDay>(entityName: "NonSchoolDay")
        nonSchoolFetch.predicate = NSPredicate(format: "date == %@", day as NSDate)
        let nonSchoolRows = try context.fetch(nonSchoolFetch)

        let overrideFetch = NSFetchRequest<CDSchoolDayOverride>(entityName: "SchoolDayOverride")
        overrideFetch.predicate = NSPredicate(format: "date == %@", day as NSDate)
        let overrideRows = try context.fetch(overrideFetch)

        let change: SchoolDayChange
        if inSession {
            let removedNonSchool = !nonSchoolRows.isEmpty
            nonSchoolRows.forEach(context.delete)
            if isWeekend, overrideRows.isEmpty {
                let override = CDSchoolDayOverride(context: context)
                override.date = day
                change = .markedSchool
            } else {
                change = removedNonSchool ? .markedSchool : .unchanged
            }
        } else {
            let removedOverride = !overrideRows.isEmpty
            overrideRows.forEach(context.delete)
            if isWeekend {
                // A weekend is out of session by default; a stray explicit row is
                // harmless but there is nothing to add.
                change = removedOverride ? .markedNonSchool : .unchanged
            } else if let existing = nonSchoolRows.first {
                let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmedReason, !trimmedReason.isEmpty, trimmedReason != existing.reason {
                    existing.reason = trimmedReason
                    change = .reasonUpdated
                } else {
                    change = .unchanged
                }
            } else {
                let nonSchoolDay = CDNonSchoolDay(context: context)
                nonSchoolDay.date = day
                let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
                nonSchoolDay.reason = (trimmedReason?.isEmpty == false) ? trimmedReason : nil
                change = .markedNonSchool
            }
        }

        if change != .unchanged {
            invalidateMonthCache(for: day)
            Self.notifySchoolDayDataChanged()
        }
        return change
    }
}
