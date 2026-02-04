import Foundation
import SwiftData

/// Categories of classroom/facility issues
enum IssueCategory: String, Codable, CaseIterable {
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
enum IssuePriority: String, Codable, CaseIterable {
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
enum IssueStatus: String, Codable, CaseIterable {
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
enum IssueActionType: String, Codable, CaseIterable {
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

/// Main issue tracking entity
@Model
final class Issue: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var modifiedAt: Date = Date()
    
    // Core fields
    var title: String = ""
    var issueDescription: String = ""
    
    // Category and priority (using manual enum pattern for SwiftData predicates)
    private var categoryRaw: String = IssueCategory.other.rawValue
    var category: IssueCategory {
        get { IssueCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    
    private var priorityRaw: String = IssuePriority.medium.rawValue
    var priority: IssuePriority {
        get { IssuePriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    
    private var statusRaw: String = IssueStatus.open.rawValue
    var status: IssueStatus {
        get { IssueStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
    
    // Related students (stored as UUIDs in string format for CloudKit compatibility)
    @Attribute(.externalStorage) private var _studentIDsData: Data? = nil
    
    @Transient
    var studentIDs: [String] {
        get {
            guard let data = _studentIDsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            _studentIDsData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
    
    // Location/context
    var location: String? = nil
    
    // Resolution tracking
    var resolvedAt: Date? = nil
    var resolutionSummary: String? = nil
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \IssueAction.issue)
    var actions: [IssueAction]? = []
    
    @Relationship(deleteRule: .cascade, inverse: \Note.issue)
    var notes: [Note]? = []
    
    init(
        title: String = "",
        description: String = "",
        category: IssueCategory = .other,
        priority: IssuePriority = .medium,
        status: IssueStatus = .open,
        studentIDs: [String] = [],
        location: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modifiedAt = Date()
        self.title = title
        self.issueDescription = description
        self.categoryRaw = category.rawValue
        self.priorityRaw = priority.rawValue
        self.statusRaw = status.rawValue
        self.studentIDs = studentIDs
        self.location = location
    }
}

/// Actions taken on an issue (conversations, agreements, follow-ups)
@Model
final class IssueAction: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var modifiedAt: Date = Date()
    
    // Parent relationship
    var issueID: String = ""
    @Relationship var issue: Issue?
    
    // Action details
    private var actionTypeRaw: String = IssueActionType.note.rawValue
    var actionType: IssueActionType {
        get { IssueActionType(rawValue: actionTypeRaw) ?? .note }
        set { actionTypeRaw = newValue.rawValue }
    }
    
    var actionDescription: String = ""
    var actionDate: Date = Date()
    
    // Who was involved (stored as UUIDs in string format)
    @Attribute(.externalStorage) private var _participantIDsData: Data? = nil
    
    @Transient
    var participantStudentIDs: [String] {
        get {
            guard let data = _participantIDsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            _participantIDsData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
    
    // Next steps or agreements
    var nextSteps: String? = nil
    var followUpRequired: Bool = false
    var followUpDate: Date? = nil
    var followUpCompleted: Bool = false
    
    init(
        issue: Issue? = nil,
        actionType: IssueActionType = .note,
        description: String = "",
        actionDate: Date = Date(),
        participantStudentIDs: [String] = [],
        nextSteps: String? = nil,
        followUpRequired: Bool = false,
        followUpDate: Date? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modifiedAt = Date()
        self.issue = issue
        self.issueID = issue?.id.uuidString ?? ""
        self.actionTypeRaw = actionType.rawValue
        self.actionDescription = description
        self.actionDate = actionDate
        self.participantStudentIDs = participantStudentIDs
        self.nextSteps = nextSteps
        self.followUpRequired = followUpRequired
        self.followUpDate = followUpDate
    }
}
