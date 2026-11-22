import Foundation

/// Lifecycle status of a book club session.
enum BookClubSessionStatus: String, CaseIterable, Identifiable, Sendable {
    case planned
    case active
    case completed
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .active: return "Active"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }

    var sortOrder: Int {
        switch self {
        case .active: return 0
        case .planned: return 1
        case .completed: return 2
        case .archived: return 3
        }
    }
}
