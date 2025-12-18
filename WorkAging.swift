import Foundation
import SwiftData

// MARK: - Aging Types
enum AgingBucket: Int, Codable, Comparable {
    case fresh = 0
    case aging = 1
    case stale = 2

    static func < (lhs: AgingBucket, rhs: AgingBucket) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgingPolicy {
    /// First bucket boundary where items start to be considered aging.
    static var agingDays: Int = 5
    /// Second bucket boundary where items are considered stale.
    static var staleDays: Int = 9
}

// MARK: - Work Aging Computation
/// Computes aging/overdue metrics for a WorkContract using lightweight inputs.
/// Callers should provide the plan items and (optionally) notes that relate to the contract.
/// This avoids schema changes and heavy relationship tracking while keeping logic centralized.
enum WorkContractAging {

    /// Returns the most recent meaningful touch date for a contract.
    /// Priority:
    /// 1) Most recent past check-in/progress/assessment plan date (from WorkPlanItem)
    /// 2) Most recent note timestamp (updatedAt, then createdAt)
    /// 3) Most recent status change timestamp (currently only completedAt if present)
    /// 4) Fallback: presentation date (if provided) or the contract's creation date
    static func lastMeaningfulTouchDate(
        for contract: WorkContract,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> Date {
        let today = AppCalendar.startOfDay(Date())

        // 1) Most recent past plan item date for progress/assessment
        let pastPlanDates: [Date] = planItems
            .filter { $0.workID == contract.id }
            .filter { item in
                if let r = item.reason {
                    switch r {
                    case .progressCheck, .assessment:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
            .map { AppCalendar.startOfDay($0.scheduledDate) }
            .filter { $0 <= today }
        let latestPlan = pastPlanDates.max()

        // 2) Most recent note timestamp
        let latestNote: Date? = notes?.map { max($0.updatedAt, $0.createdAt) }.max()

        // 3) Status change timestamp (only completedAt is tracked)
        let statusChange: Date? = contract.completedAt.map { AppCalendar.startOfDay($0) }

        // 4) Fallbacks
        let presentationDate: Date? = { if let p = presentation { return AppCalendar.startOfDay(p.presentedAt) }; return nil }()
        let created = AppCalendar.startOfDay(contract.createdAt)

        // Return the most recent non-nil in priority order
        return latestPlan ?? latestNote ?? statusChange ?? presentationDate ?? created
    }

    /// Calendar day difference between today and the last meaningful touch.
    @available(*, deprecated, message: "Use school-day overload with modelContext for business logic.")
    static func daysSinceLastTouch(
        for contract: WorkContract,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> Int {
        let last = lastMeaningfulTouchDate(for: contract, planItems: planItems, notes: notes, presentation: presentation)
        let startToday = AppCalendar.startOfDay(Date())
        let startLast = AppCalendar.startOfDay(last)
        // Count whole days by stepping with AppCalendar to respect its normalization rules
        var days = 0
        var cursor = startLast
        while cursor < startToday {
            cursor = AppCalendar.addingDays(1, to: cursor)
            days += 1
            // Safety to avoid pathological loops
            if days > 36500 { break }
        }
        return max(0, days)
    }

    /// School-day aware difference between today and the last meaningful touch.
    /// This is the authoritative version for business rules.
    static func daysSinceLastTouch(
        for contract: WorkContract,
        modelContext: ModelContext,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> Int {
        let last = lastMeaningfulTouchDate(for: contract, planItems: planItems, notes: notes, presentation: presentation)
        let startToday = AppCalendar.startOfDay(Date())
        let startLast = AppCalendar.startOfDay(last)
        var days = 0
        var cursor = startLast
        while cursor < startToday {
            if !SchoolCalendar.isNonSchoolDay(cursor, using: modelContext) {
                days += 1
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            if days > 36500 { break }
        }
        return max(0, days)
    }

    /// Maps the day difference to an AgingBucket using AgingPolicy thresholds.
    @available(*, deprecated, message: "Use school-day overload with modelContext for business logic.")
    static func agingBucket(
        for contract: WorkContract,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> AgingBucket {
        let days = daysSinceLastTouch(for: contract, planItems: planItems, notes: notes, presentation: presentation)
        if days >= AgingPolicy.staleDays { return .stale }
        if days >= AgingPolicy.agingDays { return .aging }
        return .fresh
    }

    /// Maps day difference to an AgingBucket using school days.
    /// This is the authoritative version for business rules.
    static func agingBucket(
        for contract: WorkContract,
        modelContext: ModelContext,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> AgingBucket {
        let days = daysSinceLastTouch(for: contract, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
        if days >= AgingPolicy.staleDays { return .stale }
        if days >= AgingPolicy.agingDays { return .aging }
        return .fresh
    }

    /// Convenience predicate for stale status.
    @available(*, deprecated, message: "Use school-day overload with modelContext for business logic.")
    static func isStale(
        _ contract: WorkContract,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> Bool {
        agingBucket(for: contract, planItems: planItems, notes: notes, presentation: presentation) == .stale
    }

    /// Convenience predicate for stale status using school days.
    /// This is the authoritative version for business rules.
    static func isStale(
        _ contract: WorkContract,
        modelContext: ModelContext,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil,
        presentation: Presentation? = nil
    ) -> Bool {
        agingBucket(for: contract, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation) == .stale
    }

    /// Intent-aware overdue check.
    /// True only when:
    /// - There exists a scheduled date with expectation intent (.progressCheck or .assessment)
    /// - That date is in the past (strictly before today start)
    /// - There has been no meaningful touch since before that scheduled date
    static func isOverdue(
        _ contract: WorkContract,
        planItems: [WorkPlanItem],
        lastTouch overrideLastTouch: Date? = nil
    ) -> Bool {
        let today = AppCalendar.startOfDay(Date())
        // Earliest relevant scheduled date (calendar shows earliest among relevant kinds)
        let relevant = planItems
            .filter { $0.workID == contract.id }
            .filter { item in
                if let r = item.reason {
                    switch r {
                    case .progressCheck, .assessment:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
            .map { AppCalendar.startOfDay($0.scheduledDate) }
        guard let earliest = relevant.min(), earliest < today else { return false }

        let last = overrideLastTouch ?? lastMeaningfulTouchDate(for: contract, planItems: planItems, notes: nil, presentation: nil)
        return AppCalendar.startOfDay(last) < earliest
    }
}

#if DEBUG
// Lightweight debug helper for console verification
enum WorkAgingDebug {
    static func describe(
        contract: WorkContract,
        modelContext: ModelContext,
        planItems: [WorkPlanItem],
        notes: [ScopedNote]? = nil
    ) -> String {
        let last = WorkContractAging.lastMeaningfulTouchDate(for: contract, planItems: planItems, notes: notes)
        let days = WorkContractAging.daysSinceLastTouch(for: contract, modelContext: modelContext, planItems: planItems, notes: notes)
        let bucket = WorkContractAging.agingBucket(for: contract, modelContext: modelContext, planItems: planItems, notes: notes)
        let overdue = WorkContractAging.isOverdue(contract, planItems: planItems, lastTouch: last)
        let df = DateFormatter(); df.dateStyle = .medium
        return "[school-days] last=\(df.string(from: last)) days=\(days) bucket=\(bucket) overdue=\(overdue)"
    }
}
#endif

