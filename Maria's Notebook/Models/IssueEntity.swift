import Foundation
import CoreData

@objc(Issue)
public class Issue: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var title: String
    @NSManaged public var issueDescription: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var priorityRaw: String
    @NSManaged public var statusRaw: String
    @NSManaged public var _studentIDsData: Data?
    @NSManaged public var location: String?
    @NSManaged public var resolvedAt: Date?
    @NSManaged public var resolutionSummary: String?

    // MARK: - Relationships
    @NSManaged public var actions: NSSet?
    @NSManaged public var notes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Issue", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modifiedAt = Date()
        self.title = ""
        self.issueDescription = ""
        self.categoryRaw = IssueCategory.other.rawValue
        self.priorityRaw = IssuePriority.medium.rawValue
        self.statusRaw = IssueStatus.open.rawValue
        self._studentIDsData = nil
        self.location = nil
        self.resolvedAt = nil
        self.resolutionSummary = nil
    }
}

// MARK: - Enums

extension Issue {
    enum IssueCategory: String, Codable, CaseIterable, Sendable {
        case behavioral = "Behavioral"
        case social = "Social"
        case facility = "Facility"
        case supply = "Supply"
        case safety = "Safety"
        case health = "Health"
        case communication = "Communication"
        case other = "Other"

        public var systemImage: String {
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

    enum IssuePriority: String, Codable, CaseIterable, Sendable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case urgent = "Urgent"

        public var color: String {
            switch self {
            case .low: return "gray"
            case .medium: return "blue"
            case .high: return "orange"
            case .urgent: return "red"
            }
        }
    }

    enum IssueStatus: String, Codable, CaseIterable, Sendable {
        case open = "Open"
        case investigating = "Investigating"
        case inProgress = "In Progress"
        case resolved = "Resolved"
        case closed = "Closed"

        public var systemImage: String {
            switch self {
            case .open: return "circle"
            case .investigating: return "magnifyingglass"
            case .inProgress: return "arrow.clockwise"
            case .resolved: return "checkmark.circle"
            case .closed: return "checkmark.circle.fill"
            }
        }
    }
}

// MARK: - Computed Properties

extension Issue {
    var category: IssueCategory {
        get { IssueCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var priority: IssuePriority {
        get { IssuePriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var status: IssueStatus {
        get { IssueStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    /// Student IDs decoded from binary data
    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set {
            _studentIDsData = CloudKitStringArrayStorage.encode(newValue)
            updatedAt = Date()
        }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension Issue {
    @objc(addActionsObject:)
    @NSManaged public func addToActions(_ value: IssueAction)

    @objc(removeActionsObject:)
    @NSManaged public func removeFromActions(_ value: IssueAction)

    @objc(addActions:)
    @NSManaged public func addToActions(_ values: NSSet)

    @objc(removeActions:)
    @NSManaged public func removeFromActions(_ values: NSSet)

    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
