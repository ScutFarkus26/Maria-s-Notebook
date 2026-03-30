import Foundation
import CoreData

@objc(Issue)
public class CDIssue: NSManagedObject {
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

extension CDIssue {

}

// MARK: - Computed Properties

extension CDIssue {
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

extension CDIssue {
    @objc(addActionsObject:)
    @NSManaged public func addToActions(_ value: CDIssueAction)

    @objc(removeActionsObject:)
    @NSManaged public func removeFromActions(_ value: CDIssueAction)

    @objc(addActions:)
    @NSManaged public func addToActions(_ values: NSSet)

    @objc(removeActions:)
    @NSManaged public func removeFromActions(_ values: NSSet)

    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
