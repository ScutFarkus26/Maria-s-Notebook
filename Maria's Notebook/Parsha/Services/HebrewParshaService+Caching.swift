// HebrewParshaService+Caching.swift
// Shared calendars and per-year memoization for the parsha computation.
//
// The parsha algorithm is pure but expensive: `parshaKey(forShabbat:)` rebuilds a
// year's whole 54-parsha schedule, and `shabbatotForHebrewYear` calls it once per
// Shabbat — so rendering one year was O(weeks²) calendar math. Worse, every helper
// built its own `Calendar(identifier:)`, and `Calendar(identifier: .hebrew)`
// constructs an ICU calendar each time. Because the views read all of this from
// SwiftUI computed properties, the whole cost repeated on every body pass.
//
// Everything here is derived data with no external side effects, so caching it
// changes cost, not behavior — `HebrewParshaServiceTests.goldenAnchorsMatchHebcal`
// pins the results against Hebcal either way.

import Foundation

extension HebrewParshaService {

    // MARK: - Shared Calendars

    private static var _gregorian = Calendar(identifier: .gregorian)
    private static var _hebrew = Calendar(identifier: .hebrew)

    static var gregorian: Calendar {
        observeTimeZoneChangesIfNeeded()
        return _gregorian
    }

    static var hebrew: Calendar {
        observeTimeZoneChangesIfNeeded()
        return _hebrew
    }

    // MARK: - Memoized Year Data

    /// `sedraSchedule` is a pure function of the Hebrew year. `[String]?` values are
    /// stored so a year that legitimately has no schedule caches as a miss rather
    /// than being recomputed forever.
    static var scheduleCache: [Int: [String]?] = [:]

    // Cache for `shabbatotForHebrewYear`, keyed by the cycle year it resolved to.
    // The element type mirrors that method's return type exactly, so the tuple shape
    // is fixed by the existing API rather than chosen here.
    // swiftlint:disable:next large_tuple
    static var yearShabbatotCache: [Int: [(date: Date, parshaKey: String?, festivalName: String?)]] = [:]

    private static var didObserveTimeZoneChanges = false

    /// A cached `Calendar` freezes the time zone it was built with, and every memo
    /// above derives from start-of-day boundaries in that zone. Re-seed both when the
    /// system time zone changes, so a guide who travels (or crosses a DST boundary)
    /// doesn't get dates computed against the old offset.
    private static func observeTimeZoneChangesIfNeeded() {
        guard !didObserveTimeZoneChanges else { return }
        didObserveTimeZoneChanges = true
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { invalidateCalendarCaches() }
        }
    }

    /// Rebuilds the cached calendars and drops every derived memo.
    static func invalidateCalendarCaches() {
        _gregorian = Calendar(identifier: .gregorian)
        _hebrew = Calendar(identifier: .hebrew)
        scheduleCache.removeAll()
        yearShabbatotCache.removeAll()
    }
}
