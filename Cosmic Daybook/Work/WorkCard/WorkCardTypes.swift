import SwiftUI

/// Badge types for list mode
enum WorkCardBadge: Equatable {
    /// Shows count of open participants (e.g., "3")
    case openCount(Int)
    /// Shows status text (e.g., "active", "complete")
    case status(String)
}

/// Work type visual attributes
/// Uses WorkKind styling for consistency across the app
enum WorkCardWorkType {
    case research
    case followUp
    case practice
    case report

    /// Initialize from WorkKind (preferred)
    init(from kind: WorkKind) {
        switch kind {
        case .research: self = .research
        case .followUpAssignment: self = .followUp
        case .practiceLesson: self = .practice
        case .report: self = .report
        }
    }

    /// Convert to WorkKind for consistent styling
    private var asWorkKind: WorkKind {
        switch self {
        case .research: return .research
        case .followUp: return .followUpAssignment
        case .practice: return .practiceLesson
        case .report: return .report
        }
    }

    var icon: String {
        asWorkKind.iconName
    }

    var color: Color {
        asWorkKind.color
    }
}
