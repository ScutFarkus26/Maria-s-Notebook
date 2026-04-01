import SwiftUI

/// Badge types for list mode
enum WorkCardBadge: Equatable {
    /// Shows count of open participants (e.g., "3")
    case openCount(Int)
    /// Shows status text (e.g., "active", "complete")
    case status(String)
}

/// Participant display data for compact mode
struct WorkCardParticipant: Identifiable {
    let id: UUID
    let studentID: UUID
    let name: String
    let isCompleted: Bool
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

/// Work kind visual attributes (for pill mode)
/// Wrapper that uses WorkKind styling for consistency
enum WorkCardWorkKind {
    case practiceLesson
    case followUpAssignment
    case report
    case other

    init(from kind: WorkKind?) {
        switch kind {
        case .practiceLesson: self = .practiceLesson
        case .followUpAssignment: self = .followUpAssignment
        case .report: self = .report
        case .research: self = .other
        case nil: self = .other
        }
    }

    /// Convert to WorkKind for consistent styling
    private var asWorkKind: WorkKind? {
        switch self {
        case .practiceLesson: return .practiceLesson
        case .followUpAssignment: return .followUpAssignment
        case .report: return .report
        case .other: return .research
        }
    }

    var color: Color {
        asWorkKind?.color ?? .secondary
    }
}
