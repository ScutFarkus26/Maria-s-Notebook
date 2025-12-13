import Foundation
import SwiftData

struct WorkGroupingService {
    static func sectionOrder(for grouping: WorkFilters.Grouping) -> [String] {
        switch grouping {
        case .none:
            return []
        case .type:
            return [
                WorkModel.WorkType.research.rawValue,
                WorkModel.WorkType.followUp.rawValue,
                WorkModel.WorkType.practice.rawValue
            ]
        case .date:
            return ["Today", "This Week", "Earlier"]
        case .checkIns:
            return ["Overdue", "Today", "Tomorrow", "This Week", "Future", "No Check-Ins"]
        }
    }
    
    static func sectionIcon(for key: String) -> String {
        switch key {
        case WorkModel.WorkType.research.rawValue:
            return "magnifyingglass.circle.fill"
        case WorkModel.WorkType.followUp.rawValue:
            return "bolt.circle.fill"
        case WorkModel.WorkType.practice.rawValue:
            return "arrow.triangle.2.circlepath.circle.fill"
        case "Today":
            return "sun.max.fill"
        case "This Week":
            return "calendar"
        case "Tomorrow":
            return "sunrise.fill"
        case "Overdue":
            return "exclamationmark.triangle.fill"
        case "Future":
            return "calendar.badge.clock"
        case "No Check-Ins":
            return "calendar.badge.exclamationmark"
        default:
            return "clock"
        }
    }
    
    static func groupByType(_ works: [WorkModel]) -> [String: [WorkModel]] {
        Dictionary(grouping: works, by: { $0.workType.rawValue })
    }
    
    static func groupByDate(_ works: [WorkModel], linkedDate: @escaping (WorkModel) -> Date) -> [String: [WorkModel]] {
        let cal = Calendar.current
        let today = Date()
        return Dictionary(grouping: works, by: { work in
            let d = linkedDate(work)
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            return "Earlier"
        })
    }
    
    /// Deprecated: This synchronous implementation iterates `work.checkIns` and can fault each relationship on the main thread.
    /// Prefer using `WorkGroupingServiceActor.groupByCheckIns(for:)` (or the wrapper `WorkGroupingService.groupByCheckIns(workIDs:using:)`)
    /// to perform the work off the main thread with a single optimized fetch.
    static func groupByCheckIns(_ works: [WorkModel]) -> [String: [WorkModel]] {
        let cal = Calendar.current
        let today = Date()
        return Dictionary(grouping: works, by: { work in
            guard let checkIn = nextIncompleteCheckIn(for: work) else {
                return "No Check-Ins"
            }
            let d = checkIn.date
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            if d < today { return "Overdue" }
            return "Future"
        })
    }
    
    static func itemsForSection(
        _ key: String,
        grouping: WorkFilters.Grouping,
        works: [WorkModel],
        linkedDate: @escaping (WorkModel) -> Date
    ) -> [WorkModel] {
        switch grouping {
        case .none:
            return []
        case .type:
            return groupByType(works)[key] ?? []
        case .date:
            return groupByDate(works, linkedDate: linkedDate)[key] ?? []
        case .checkIns:
            return groupByCheckIns(works)[key] ?? []
        }
    }
    
    private static func nextIncompleteCheckIn(for work: WorkModel) -> WorkCheckIn? {
        let incomplete = work.checkIns.filter { $0.status != .completed && $0.status != .skipped }
        return incomplete.min(by: { $0.date < $1.date })
    }
    
    /// Asynchronous, thread-safe grouping that delegates to `WorkGroupingServiceActor`.
    static func groupByCheckIns(workIDs: [UUID], using actor: WorkGroupingServiceActor) async throws -> [String: [UUID]] {
        try await actor.groupByCheckIns(for: workIDs)
    }
}
@ModelActor
actor WorkGroupingServiceActor {
    /// Performs the check-in grouping off the main thread using this actor's `modelContext`.
    /// - Parameter workIDs: The app-level `UUID` identifiers of the work items to group.
    /// - Returns: A dictionary from section key (e.g. "Today", "Overdue", etc.) to ordered work IDs.
    func groupByCheckIns(for workIDs: [UUID]) async throws -> [String: [UUID]] {
        // Fast path
        if workIDs.isEmpty { return [:] }

        // Fetch all check-ins for the provided works in one query.
        // We intentionally avoid filtering by status in the predicate because `status` is computed
        // and the persisted `statusRaw` is private to its declaring file. We'll filter in memory.
        let descriptor = FetchDescriptor<WorkCheckIn>(
            predicate: #Predicate { ci in
                workIDs.contains(ci.workID)
            },
            sortBy: [SortDescriptor(\WorkCheckIn.date, order: .forward)]
        )

        let fetched = try modelContext.fetch(descriptor)

        // Keep only incomplete check-ins, preserving order by date due to the fetch sort above.
        let incomplete = fetched.filter { $0.status != .completed && $0.status != .skipped }

        // Compute the next (earliest) incomplete check-in per work ID.
        var nextByWorkID: [UUID: WorkCheckIn] = [:]
        for ci in incomplete {
            let wid = ci.workID
            if let current = nextByWorkID[wid] {
                if ci.date < current.date { nextByWorkID[wid] = ci }
            } else {
                nextByWorkID[wid] = ci
            }
        }

        // Classification logic identical to the original synchronous implementation.
        let cal = Calendar.current
        let today = Date()
        func classify(_ d: Date) -> String {
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            if d < today { return "Overdue" }
            return "Future"
        }

        // Build grouped result preserving the input `workIDs` order within each bucket.
        var groups: [String: [UUID]] = [:]
        for wid in workIDs {
            if let next = nextByWorkID[wid] {
                let key = classify(next.date)
                groups[key, default: []].append(wid)
            } else {
                groups["No Check-Ins", default: []].append(wid)
            }
        }
        return groups
    }
}

