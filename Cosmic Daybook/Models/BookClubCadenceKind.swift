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

