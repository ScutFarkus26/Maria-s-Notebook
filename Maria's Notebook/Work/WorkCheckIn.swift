import Foundation
import SwiftUI

enum WorkCheckInStatus: String, Codable, CaseIterable, Sendable {
    case scheduled = "Scheduled"
    case completed = "Completed"
    case skipped = "Skipped"

    // MARK: - Styling

    /// Standard color for this check-in status
    var color: Color {
        switch self {
        case .completed: return .green
        case .skipped: return .red
        case .scheduled: return .orange
        }
    }

    /// System icon name for this status
    var iconName: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .scheduled: return "clock"
        }
    }

    /// Display label for menus and UI
    var displayLabel: String {
        switch self {
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .scheduled: return "Scheduled"
        }
    }

    /// Menu action label (e.g., "Mark Completed")
    var menuActionLabel: String {
        switch self {
        case .completed: return "Mark Completed"
        case .skipped: return "Mark Skipped"
        case .scheduled: return "Mark Scheduled"
        }
    }
}
