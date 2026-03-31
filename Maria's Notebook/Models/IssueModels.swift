import Foundation

/// Categories of classroom/facility issues
enum IssueCategory: String, Codable, CaseIterable, Sendable {
    case behavioral = "Behavioral"
    case social = "Social"
    case facility = "Facility"
    case supply = "Supply"
    case safety = "Safety"
    case health = "Health"
    case communication = "Communication"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .behavioral: return "exclamationmark.bubble"
        case .social: return "person.2"
        case .facility: return "wrench.and.screwdriver"
        case .supply: return "shippingbox"
        case .safety: return "shield"
        case .health: return "cross.case"
        case .communication: return "message"
        case .other: return "questionmark.circle"
        }
    }
}

/// Priority levels for issues
enum IssuePriority: String, Codable, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"

    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}

/// Current status of an issue
enum IssueStatus: String, Codable, CaseIterable, Sendable {
    case open = "Open"
    case investigating = "Investigating"
    case inProgress = "In Progress"
    case resolved = "Resolved"
    case closed = "Closed"

    var systemImage: String {
        switch self {
        case .open: return "circle"
        case .investigating: return "magnifyingglass"
        case .inProgress: return "arrow.clockwise"
        case .resolved: return "checkmark.circle"
        case .closed: return "checkmark.circle.fill"
        }
    }
}

/// Type of action taken on an issue
enum IssueActionType: String, Codable, CaseIterable, Sendable {
    case initialReport = "Initial Report"
    case conversation = "Conversation"
    case agreement = "Agreement"
    case followUp = "Follow-up"
    case observation = "Observation"
    case resolution = "Resolution"
    case note = "Note"

    var systemImage: String {
        switch self {
        case .initialReport: return "flag"
        case .conversation: return "bubble.left.and.bubble.right"
        case .agreement: return "hand.thumbsup"
        case .followUp: return "arrow.turn.up.right"
        case .observation: return "eye"
        case .resolution: return "checkmark.seal"
        case .note: return "note.text"
        }
    }
}
