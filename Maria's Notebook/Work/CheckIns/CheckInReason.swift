import Foundation

/// Reason for scheduling a work check-in.
enum CheckInReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case progressCheck
    case dueDate
    case assessment
    case followUp
    case studentRequest
    case other

    var id: String { rawValue }

    /// Maps to a human-readable purpose string for the WorkCheckIn entity.
    var purpose: String {
        switch self {
        case .progressCheck: return "Progress Check"
        case .dueDate: return "Due Date"
        case .assessment: return "Assessment"
        case .followUp: return "Follow Up"
        case .studentRequest: return "Student Request"
        case .other: return "Other"
        }
    }
}
