import Foundation
import CoreData

// MARK: - Aging Types
enum AgingBucket: Int, Codable, Comparable, Sendable {
    case fresh = 0
    case aging = 1
    case stale = 2

    static func < (lhs: AgingBucket, rhs: AgingBucket) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct AgingPolicy {
    /// First bucket boundary where items start to be considered aging.
    static let agingDays: Int = 5

    /// School days of silence after which work counts as stale.
    ///
    /// The single stale threshold in the app. It decides the card's colour
    /// indicator, the Today screen's stale list, the lesson list's warning, and
    /// — through `LessonsAndWorkTriage.staleSchoolDays` — whether work lands in
    /// the Attention list. These used to be 9 here and 10 in the triage rule,
    /// so a card could look stale without being asked for.
    static let staleDays: Int = 10
}

// MARK: - CDWorkModel Aging Policy
/// Computes aging/overdue metrics for a CDWorkModel.
/// Uses school-day aware calculations for accurate business rules.
enum WorkAgingPolicy {
    /// Returns the most recent meaningful touch date for a work model.
    /// Priority:
    /// 1) CDWorkModel.lastTouchedAt (if explicitly set)
    /// 2) Most recent past completed check-in date (from CDWorkCheckIn)
    /// 3) Most recent note timestamp (updatedAt, then createdAt)
    /// 4) Most recent status change timestamp (completedAt if present)
    /// 5) Fallback: assignedAt or createdAt
    nonisolated static func lastMeaningfulTouchDate(
        for work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> Date {
        let today = AppCalendar.startOfDay(Date())

        // 1) Explicit lastTouchedAt (highest priority)
        if let lastTouched = work.lastTouchedAt {
            return AppCalendar.startOfDay(lastTouched)
        }

        // 2) Most recent past completed check-in date
        let workCheckIns = checkIns ?? ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
        let pastCheckInDates: [Date] = workCheckIns
            .filter { $0.status == .completed }
            .map { AppCalendar.startOfDay($0.date ?? .distantPast) }
            .filter { $0 <= today }
        let latestCheckIn = pastCheckInDates.max()

        // 3) Most recent note timestamp
        let workNotes = notes ?? ((work.unifiedNotes?.allObjects as? [CDNote]) ?? [])
        let latestNote: Date? = workNotes.map { max($0.updatedAt ?? .distantPast, $0.createdAt ?? .distantPast) }.max()

        // 4) Status change timestamp (completedAt)
        let statusChange: Date? = work.completedAt.map { AppCalendar.startOfDay($0) }

        // 5) Fallbacks
        let assigned = AppCalendar.startOfDay(work.assignedAt ?? Date())

        // Return the most recent non-nil in priority order
        // CDNote: assigned is non-optional, so it's always available as final fallback
        return latestCheckIn ?? latestNote ?? statusChange ?? assigned
    }

    /// School-day aware difference between today and the last meaningful touch.
    /// This is the authoritative version for business rules.
    nonisolated static func daysSinceLastTouch(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> Int {
        // Clamped to the school-year counter epoch so work that was last touched in a previous
        // year ages from the first day of this one instead of arriving stale on day one.
        let last = SchoolYearCounters.countFrom(
            lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        )
        let today = AppCalendar.startOfDay(Date())
        return SchoolDayChecker.schoolDaysBetween(start: last, end: today, using: context)
    }

    /// Maps day difference to an AgingBucket using school days.
    /// Returns `.fresh` while work is intentionally resting.
    nonisolated static func agingBucket(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> AgingBucket {
        if let until = work.restingUntil, until > AppCalendar.startOfDay(Date()) {
            return .fresh
        }
        let days = daysSinceLastTouch(for: work, using: context, checkIns: checkIns, notes: notes)
        if days >= AgingPolicy.staleDays { return .stale }
        if days >= AgingPolicy.agingDays { return .aging }
        return .fresh
    }

    /// Convenience predicate for stale status using school days.
    nonisolated static func isStale(
        _ work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> Bool {
        agingBucket(for: work, using: context, checkIns: checkIns, notes: notes) == .stale
    }

}
