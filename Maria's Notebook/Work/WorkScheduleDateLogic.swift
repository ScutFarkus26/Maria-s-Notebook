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

    init(
        primaryDate: Date?, primaryKind: WorkScheduleDateKind?,
        secondaryDate: Date?, secondaryKind: WorkScheduleDateKind?
    ) {
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

    /// Compute schedule dates from a collection of check-ins.
    /// - Parameter items: All check-ins relevant to a single work item.
    /// - Returns: Normalized primary and optional secondary dates.
    static func compute(forCheckIns items: [WorkCheckIn]) -> WorkScheduleDates {
        // Consider only check-in and due items based on purpose
        let normalized: [(kind: WorkScheduleDateKind, date: Date)] = items.compactMap { item in
            let purpose = item.purpose.lowercased()
            if purpose.contains("progress") || purpose.contains("assessment") || purpose.contains("check") {
                return (.checkIn, AppCalendar.startOfDay(item.date))
            } else if purpose.contains("due") {
                return (.due, AppCalendar.startOfDay(item.date))
            } else {
                // Default to check-in for other purposes
                return (.checkIn, AppCalendar.startOfDay(item.date))
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

    /// Label to display for a given schedule date kind.
    static func label(for kind: WorkScheduleDateKind) -> String {
        switch kind {
        case .checkIn: return "Check-in"
        case .due: return "Due"
        }
    }

    // MARK: - Private
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}
