import Foundation

/// Meeting cadence options for a book club session.
enum BookClubCadenceKind: String, CaseIterable, Identifiable, Sendable {
    case weekly
    case biweekly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every other week"
        case .custom: return "Custom days"
        }
    }
}

/// Fully resolved cadence used by the schedule generator.
/// `.custom` carries a weekday mask — bit 1 = Sunday, bit 2 = Monday, … bit 7 = Saturday.
enum BookClubCadence: Sendable {
    case weekly(weekday: Int)
    case biweekly(weekday: Int)
    case custom(weekdayMask: Int64)

    var kind: BookClubCadenceKind {
        switch self {
        case .weekly: return .weekly
        case .biweekly: return .biweekly
        case .custom: return .custom
        }
    }
}
