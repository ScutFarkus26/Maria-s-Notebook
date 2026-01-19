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
enum WorkCardWorkType {
    case research
    case followUp
    case practice
    case report

    init(from workType: WorkModel.WorkType) {
        switch workType {
        case .research: self = .research
        case .followUp: self = .followUp
        case .practice: self = .practice
        case .report: self = .report
        }
    }

    var icon: String {
        switch self {
        case .research: return "magnifyingglass"
        case .followUp: return "bolt.fill"
        case .practice: return "arrow.triangle.2.circlepath"
        case .report: return "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        case .report: return .green
        }
    }
}

/// Work kind visual attributes (for pill mode)
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
        default: self = .other
        }
    }

    var color: Color {
        switch self {
        case .practiceLesson: return .purple
        case .followUpAssignment: return .orange
        case .report: return .green
        case .other: return .teal
        }
    }
}
