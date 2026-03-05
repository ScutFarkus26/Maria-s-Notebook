import Foundation
import SwiftData

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
    /// Marked nonisolated(unsafe) because this is a static configuration constant accessed
    /// from multiple isolation domains. Safe because it's initialized once and never mutated after app launch.
    nonisolated(unsafe) static var agingDays: Int = 5
    
    /// Second bucket boundary where items are considered stale.
    /// Marked nonisolated(unsafe) because this is a static configuration constant accessed
    /// from multiple isolation domains. Safe because it's initialized once and never mutated after app launch.
    nonisolated(unsafe) static var staleDays: Int = 9
}

// MARK: - WorkModel Aging Policy
/// Computes aging/overdue metrics for a WorkModel.
/// Uses school-day aware calculations for accurate business rules.
enum WorkAgingPolicy {
    /// Returns the most recent meaningful touch date for a work model.
    /// Priority:
    /// 1) WorkModel.lastTouchedAt (if explicitly set)
    /// 2) Most recent past completed check-in date (from WorkCheckIn)
    /// 3) Most recent note timestamp (updatedAt, then createdAt)
    /// 4) Most recent status change timestamp (completedAt if present)
    /// 5) Fallback: assignedAt or createdAt
    nonisolated static func lastMeaningfulTouchDate(
        for work: WorkModel,
        checkIns: [WorkCheckIn]? = nil,
        notes: [Note]? = nil
    ) -> Date {
        let today = AppCalendar.startOfDay(Date())
        
        // 1) Explicit lastTouchedAt (highest priority)
        if let lastTouched = work.lastTouchedAt {
            return AppCalendar.startOfDay(lastTouched)
        }
        
        // 2) Most recent past completed check-in date
        let workCheckIns = checkIns ?? (work.checkIns ?? [])
        let pastCheckInDates: [Date] = workCheckIns
            .filter { $0.status == .completed }
            .map { AppCalendar.startOfDay($0.date) }
            .filter { $0 <= today }
        let latestCheckIn = pastCheckInDates.max()
        
        // 3) Most recent note timestamp
        let workNotes = notes ?? (work.unifiedNotes ?? [])
        let latestNote: Date? = workNotes.map { max($0.updatedAt, $0.createdAt) }.max()
        
        // 4) Status change timestamp (completedAt)
        let statusChange: Date? = work.completedAt.map { AppCalendar.startOfDay($0) }
        
        // 5) Fallbacks
        let assigned = AppCalendar.startOfDay(work.assignedAt)
        
        // Return the most recent non-nil in priority order
        // Note: assigned is non-optional, so it's always available as final fallback
        return latestCheckIn ?? latestNote ?? statusChange ?? assigned
    }
    
    /// School-day aware difference between today and the last meaningful touch.
    /// This is the authoritative version for business rules.
    nonisolated static func daysSinceLastTouch(
        for work: WorkModel,
        modelContext: ModelContext,
        checkIns: [WorkCheckIn]? = nil,
        notes: [Note]? = nil
    ) -> Int {
        let last = lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        let today = AppCalendar.startOfDay(Date())
        return SchoolDayChecker.schoolDaysBetween(start: last, end: today, using: modelContext)
    }
    
    /// Maps day difference to an AgingBucket using school days.
    nonisolated static func agingBucket(
        for work: WorkModel,
        modelContext: ModelContext,
        checkIns: [WorkCheckIn]? = nil,
        notes: [Note]? = nil
    ) -> AgingBucket {
        let days = daysSinceLastTouch(for: work, modelContext: modelContext, checkIns: checkIns, notes: notes)
        if days >= AgingPolicy.staleDays { return .stale }
        if days >= AgingPolicy.agingDays { return .aging }
        return .fresh
    }
    
    /// Convenience predicate for stale status using school days.
    nonisolated static func isStale(
        _ work: WorkModel,
        modelContext: ModelContext,
        checkIns: [WorkCheckIn]? = nil,
        notes: [Note]? = nil
    ) -> Bool {
        agingBucket(for: work, modelContext: modelContext, checkIns: checkIns, notes: notes) == .stale
    }
    
    /// Intent-aware overdue check.
    /// True only when:
    /// - There exists a dueAt date (or due date from check-ins)
    /// - That date is in the past (strictly before today start)
    /// - There has been no meaningful touch since before that due date
    nonisolated static func isOverdue(
        _ work: WorkModel,
        checkIns: [WorkCheckIn]? = nil,
        lastTouch overrideLastTouch: Date? = nil
    ) -> Bool {
        let today = AppCalendar.startOfDay(Date())
        
        // Check WorkModel.dueAt first
        if let dueAt = work.dueAt {
            let dueDay = AppCalendar.startOfDay(dueAt)
            guard dueDay < today else { return false }
            
            let last = overrideLastTouch ?? lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: nil)
            return AppCalendar.startOfDay(last) < dueDay
        }
        
        // Fallback: check scheduled check-ins for due dates
        let workCheckIns = checkIns ?? (work.checkIns ?? [])
        let dueCheckIns = workCheckIns
            .filter { $0.status == .scheduled }
            .map { AppCalendar.startOfDay($0.date) }
            .filter { $0 < today }
        
        guard let earliestDue = dueCheckIns.min() else { return false }
        
        let last: Date
        if let override = overrideLastTouch {
            last = override
        } else {
            last = lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: nil)
        }
        
        return AppCalendar.startOfDay(last) < earliestDue
    }
    
    /// Check if work is due today
    nonisolated static func isDueToday(
        _ work: WorkModel,
        checkIns: [WorkCheckIn]? = nil
    ) -> Bool {
        let today = AppCalendar.startOfDay(Date())
        
        if let dueAt = work.dueAt {
            return AppCalendar.startOfDay(dueAt) == today
        }
        
        let workCheckIns = checkIns ?? (work.checkIns ?? [])
        return workCheckIns.contains { $0.status == .scheduled && AppCalendar.startOfDay($0.date) == today }
    }
    
    /// Check if work is upcoming (due in 1-2 days)
    nonisolated static func isUpcoming(
        _ work: WorkModel,
        checkIns: [WorkCheckIn]? = nil
    ) -> Bool {
        let today = AppCalendar.startOfDay(Date())
        let tomorrow = AppCalendar.addingDays(1, to: today)
        let dayAfter = AppCalendar.addingDays(2, to: today)
        
        if let dueAt = work.dueAt {
            let dueDay = AppCalendar.startOfDay(dueAt)
            return (dueDay == tomorrow || dueDay == dayAfter) && dueDay > today
        }
        
        let workCheckIns = checkIns ?? (work.checkIns ?? [])
        return workCheckIns.contains { checkIn in
            guard checkIn.status == .scheduled else { return false }
            let checkInDay = AppCalendar.startOfDay(checkIn.date)
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
    
    /// Determine urgency bucket for a work item
    nonisolated static func urgencyBucket(
        for work: WorkModel,
        modelContext: ModelContext,
        checkIns: [WorkCheckIn]? = nil,
        notes: [Note]? = nil
    ) -> UrgencyBucket {
        if isStale(work, modelContext: modelContext, checkIns: checkIns, notes: notes) {
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
        work: WorkModel,
        modelContext: ModelContext,
        checkIns: [WorkCheckIn]? = nil,
        notes: [Note]? = nil
    ) -> String {
        let last = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        let days = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: modelContext, checkIns: checkIns, notes: notes)
        let bucket = WorkAgingPolicy.agingBucket(for: work, modelContext: modelContext, checkIns: checkIns, notes: notes)
        let overdue = WorkAgingPolicy.isOverdue(work, checkIns: checkIns, lastTouch: last)
        let df = DateFormatter(); df.dateStyle = .medium
        return "[school-days] last=\(df.string(from: last)) days=\(days) bucket=\(bucket) overdue=\(overdue)"
    }
}
#endif
