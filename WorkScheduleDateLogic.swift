import Foundation

/// The kind of schedule date a work item can have for planning purposes.
enum WorkScheduleDateKind: Equatable {
    case checkIn
    case due
}

/// A normalized representation of the dates used to place and label a work item on the calendar.
/// - primaryDate/Kind is the date that should be used by the calendar for placement.
/// - secondaryDate/Kind is the other date (if both exist) and can be shown in detail UI.
struct WorkScheduleDates: Equatable {
    var primaryDate: Date?
    var primaryKind: WorkScheduleDateKind?
    var secondaryDate: Date?
    var secondaryKind: WorkScheduleDateKind?

    var hasPrimary: Bool { primaryDate != nil && primaryKind != nil }

    init(primaryDate: Date?, primaryKind: WorkScheduleDateKind?, secondaryDate: Date?, secondaryKind: WorkScheduleDateKind?) {
        self.primaryDate = primaryDate
        self.primaryKind = primaryKind
        self.secondaryDate = secondaryDate
        self.secondaryKind = secondaryKind
    }
}

/// Centralized logic for computing and labeling schedule dates for work items.
/// Always normalize using AppCalendar.startOfDay(_:) to match Planning/Agenda.
enum WorkScheduleDateLogic {
    /// Consistent primary label used across the app when referring to the calendar date.
    static let primaryLabel: String = "Calendar"

    /// Compute schedule dates from a collection of plan items.
    /// - Parameter items: All plan items relevant to a single work item.
    /// - Returns: Normalized primary and optional secondary dates.
    static func compute(forPlanItems items: [WorkPlanItem]) -> WorkScheduleDates {
        // Consider only check-in and due items
        let normalized: [(kind: WorkScheduleDateKind, date: Date)] = items.compactMap { item in
            guard let reason = item.reason else { return nil }
            switch reason {
            case .progressCheck, .assessment:
                return (.checkIn, AppCalendar.startOfDay(item.scheduledDate))
            case .dueDate:
                return (.due, AppCalendar.startOfDay(item.scheduledDate))
            default:
                return nil
            }
        }

        // Find earliest per kind
        let earliestCheckIn = normalized.filter { $0.kind == .checkIn }.map { $0.date }.min()
        let earliestDue = normalized.filter { $0.kind == .due }.map { $0.date }.min()

        // Determine primary and secondary
        switch (earliestCheckIn, earliestDue) {
        case (nil, nil):
            return WorkScheduleDates(primaryDate: nil, primaryKind: nil, secondaryDate: nil, secondaryKind: nil)
        case (let c?, nil):
            return WorkScheduleDates(primaryDate: c, primaryKind: .checkIn, secondaryDate: nil, secondaryKind: nil)
        case (nil, let d?):
            return WorkScheduleDates(primaryDate: d, primaryKind: .due, secondaryDate: nil, secondaryKind: nil)
        case (let c?, let d?):
            if c <= d {
                return WorkScheduleDates(primaryDate: c, primaryKind: .checkIn, secondaryDate: d, secondaryKind: .due)
            } else {
                return WorkScheduleDates(primaryDate: d, primaryKind: .due, secondaryDate: c, secondaryKind: .checkIn)
            }
        }
    }

    /// Compute schedule dates for a given contract by filtering plan items.
    static func compute(for contract: WorkContract, allPlanItems: [WorkPlanItem]) -> WorkScheduleDates {
        let items = allPlanItems.filter { $0.workID == contract.id }
        return compute(forPlanItems: items)
    }

    /// Human-readable label for a given kind.
    @MainActor static func reasonDisplayLabel(for reason: WorkPlanItem.Reason) -> String {
        switch reason {
        case .progressCheck, .assessment:
            return label(for: .checkIn)
        case .dueDate:
            return label(for: .due)
        default:
            return reason.label
        }
    }

    /// Optional icon for UI adornment.
    static func iconName(for kind: WorkScheduleDateKind) -> String {
        switch kind {
        case .checkIn: return "checkmark.circle"
        case .due: return "exclamationmark.circle"
        }
    }

    /// Consistent date formatting for display in labels.
    static func formattedDate(_ date: Date) -> String {
        return Self.dateFormatter.string(from: date)
    }

    /// Label to display for a given WorkPlanItem.Reason using shared semantics.
    static func label(for kind: WorkScheduleDateKind) -> String {
        switch kind {
        case .checkIn: return "Check-in"
        case .due: return "Due"
        }
    }

    /// Fallback display: compute the next meaningful date from any plan items when no primary (check-in/due) exists.
    /// Picks the earliest upcoming date; if none, the latest past; otherwise the earliest overall.
    /// Returns the date and a display label for its reason.
    static func nextAnyDate(forPlanItems items: [WorkPlanItem]) -> (date: Date, label: String)? {
        guard !items.isEmpty else { return nil }
        let today = AppCalendar.startOfDay(Date())
        let normalized = items.map { ($0, AppCalendar.startOfDay($0.scheduledDate)) }
        let upcoming = normalized.filter { $0.1 >= today }.sorted { $0.1 < $1.1 }
        if let first = upcoming.first { return (first.1, first.0.reason.map(reasonDisplayLabel(for:)) ?? "Scheduled") }
        let past = normalized.filter { $0.1 < today }.sorted { $0.1 > $1.1 }
        if let latestPast = past.first { return (latestPast.1, latestPast.0.reason.map(reasonDisplayLabel(for:)) ?? "Scheduled") }
        let any = normalized.sorted { $0.1 < $1.1 }.first!
        return (any.1, any.0.reason.map(reasonDisplayLabel(for:)) ?? "Scheduled")
    }

    // MARK: - Private
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

