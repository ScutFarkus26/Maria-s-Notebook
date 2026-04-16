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

struct AgingPolicy {
    /// First bucket boundary where items start to be considered aging.
    static let agingDays: Int = 5

    /// Second bucket boundary where items are considered stale.
    static let staleDays: Int = 9
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

    /// Returns the most recent scheduling-action date for a work model.
    /// Like `lastMeaningfulTouchDate` but excludes notes — used by `isOverdue()`
    /// so that adding a note alone does not clear the overdue flag.
    /// Only scheduling actions (completing check-ins, extending due dates) clear overdue.
    nonisolated static func lastSchedulingActionDate(
        for work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil
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

        // 3) SKIP notes — notes are documentation, not scheduling actions

        // 4) Status change timestamp (completedAt)
        let statusChange: Date? = work.completedAt.map { AppCalendar.startOfDay($0) }

        // 5) Fallbacks
        let assigned = AppCalendar.startOfDay(work.assignedAt ?? Date())

        return latestCheckIn ?? statusChange ?? assigned
    }
    
    /// School-day aware difference between today and the last meaningful touch.
    /// This is the authoritative version for business rules.
    nonisolated static func daysSinceLastTouch(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> Int {
        let last = lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        let today = AppCalendar.startOfDay(Date())
        return SchoolDayChecker.schoolDaysBetween(start: last, end: today, using: context)
    }

    // Deprecated ModelContext overload for daysSinceLastTouch removed.

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

    // Deprecated ModelContext overload for agingBucket removed.

    /// Convenience predicate for stale status using school days.
    nonisolated static func isStale(
        _ work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> Bool {
        agingBucket(for: work, using: context, checkIns: checkIns, notes: notes) == .stale
    }

    // Deprecated ModelContext overload for isStale removed.

    /// Intent-aware overdue check.
    /// True only when:
    /// - There exists a dueAt date (or due date from check-ins)
    /// - That date is in the past (strictly before today start)
    /// - There has been no scheduling action since before that due date
    /// Note: Adding a note alone does NOT clear overdue — only scheduling
    /// actions (completing/rescheduling check-ins, extending due dates) do.
    nonisolated static func isOverdue(
        _ work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil,
        lastTouch overrideLastTouch: Date? = nil
    ) -> Bool {
        if let until = work.restingUntil, until > AppCalendar.startOfDay(Date()) {
            return false
        }
        let today = AppCalendar.startOfDay(Date())

        // Check CDWorkModel.dueAt first
        if let dueAt = work.dueAt {
            let dueDay = AppCalendar.startOfDay(dueAt)
            guard dueDay < today else { return false }

            let last = overrideLastTouch ?? lastSchedulingActionDate(for: work, checkIns: checkIns)
            return AppCalendar.startOfDay(last) < dueDay
        }

        // Fallback: check scheduled check-ins for due dates
        let workCheckIns = checkIns ?? ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
        let dueCheckIns = workCheckIns
            .filter { $0.status == .scheduled }
            .map { AppCalendar.startOfDay($0.date ?? .distantPast) }
            .filter { $0 < today }

        guard let earliestDue = dueCheckIns.min() else { return false }

        let last: Date
        if let override = overrideLastTouch {
            last = override
        } else {
            last = lastSchedulingActionDate(for: work, checkIns: checkIns)
        }

        return AppCalendar.startOfDay(last) < earliestDue
    }
    
    /// Check if work is due today. Returns false while work is resting.
    nonisolated static func isDueToday(
        _ work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil
    ) -> Bool {
        if let until = work.restingUntil, until > AppCalendar.startOfDay(Date()) {
            return false
        }
        let today = AppCalendar.startOfDay(Date())
        
        if let dueAt = work.dueAt {
            return AppCalendar.startOfDay(dueAt) == today
        }
        
        let workCheckIns = checkIns ?? ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
        return workCheckIns.contains { $0.status == .scheduled && AppCalendar.startOfDay($0.date ?? .distantPast) == today }
    }

    /// Check if work is upcoming (due in 1-2 days). Returns false while work is resting.
    nonisolated static func isUpcoming(
        _ work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil
    ) -> Bool {
        if let until = work.restingUntil, until > AppCalendar.startOfDay(Date()) {
            return false
        }
        let today = AppCalendar.startOfDay(Date())
        let tomorrow = AppCalendar.addingDays(1, to: today)
        let dayAfter = AppCalendar.addingDays(2, to: today)
        
        if let dueAt = work.dueAt {
            let dueDay = AppCalendar.startOfDay(dueAt)
            return (dueDay == tomorrow || dueDay == dayAfter) && dueDay > today
        }
        
        let workCheckIns = checkIns ?? ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
        return workCheckIns.contains { checkIn in
            guard checkIn.status == .scheduled else { return false }
            let checkInDay = AppCalendar.startOfDay(checkIn.date ?? .distantPast)
            return (checkInDay == tomorrow || checkInDay == dayAfter) && checkInDay > today
        }
    }
    
    /// Urgency bucket for inbox sorting (none, upcoming, today, overdue, stale)
    enum UrgencyBucket: Int, Comparable {
        case none = 0
        case upcoming = 1
        case today = 2
        case overdue = 3
        case stale = 4
        
        static func < (lhs: UrgencyBucket, rhs: UrgencyBucket) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    /// Determine urgency bucket for a work item. Returns `.none` while work is resting.
    nonisolated static func urgencyBucket(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> UrgencyBucket {
        if let until = work.restingUntil, until > AppCalendar.startOfDay(Date()) {
            return .none
        }
        if isStale(work, using: context, checkIns: checkIns, notes: notes) {
            return .stale
        }
        if isOverdue(work, checkIns: checkIns) {
            return .overdue
        }
        if isDueToday(work, checkIns: checkIns) {
            return .today
        }
        if isUpcoming(work, checkIns: checkIns) {
            return .upcoming
        }
        return .none
    }
}

#if DEBUG
// Lightweight debug helper for console verification
enum WorkAgingDebug {
    static func describe(
        work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil
    ) -> String {
        let last = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        let days = WorkAgingPolicy.daysSinceLastTouch(
            for: work, using: context,
            checkIns: checkIns, notes: notes
        )
        let bucket = WorkAgingPolicy.agingBucket(
            for: work, using: context,
            checkIns: checkIns, notes: notes
        )
        let schedulingLast = WorkAgingPolicy.lastSchedulingActionDate(for: work, checkIns: checkIns)
        let overdue = WorkAgingPolicy.isOverdue(work, checkIns: checkIns, lastTouch: schedulingLast)
        let lastStr = DateFormatters.mediumDate.string(from: last)
        return "[school-days] last=\(lastStr) days=\(days) bucket=\(bucket) overdue=\(overdue)"
    }
}
#endif
