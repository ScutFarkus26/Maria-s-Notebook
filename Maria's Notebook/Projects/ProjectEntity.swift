import Foundation
import CoreData

@objc(Project)
public class Project: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var title: String
    @NSManaged public var bookTitle: String?
    @NSManaged public var memberStudentIDs: NSObject?  // Transformable [String]
    @NSManaged public var isActive: Bool

    // MARK: - Relationships
    @NSManaged public var sharedTemplates: NSSet?
    @NSManaged public var sessions: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Project", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.title = ""
        self.bookTitle = nil
        self.memberStudentIDs = [] as NSArray
        self.isActive = true
    }
}

// MARK: - Computed Properties

extension Project {
    /// Access memberStudentIDs as a Swift [String] array
    var memberStudentIDsArray: [String] {
        get { (memberStudentIDs as? [String]) ?? [] }
        set { memberStudentIDs = newValue as NSArray }
    }

    /// Convenience computed property to get memberStudentIDs as UUIDs
    var memberStudentUUIDs: [UUID] {
        get { memberStudentIDsArray.compactMap { UUID(uuidString: $0) } }
        set { memberStudentIDsArray = newValue.map(\.uuidString) }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension Project {
    @objc(addSharedTemplatesObject:)
    @NSManaged public func addToSharedTemplates(_ value: ProjectAssignmentTemplate)

    @objc(removeSharedTemplatesObject:)
    @NSManaged public func removeFromSharedTemplates(_ value: ProjectAssignmentTemplate)

    @objc(addSharedTemplates:)
    @NSManaged public func addToSharedTemplates(_ values: NSSet)

    @objc(removeSharedTemplates:)
    @NSManaged public func removeFromSharedTemplates(_ values: NSSet)

    @objc(addSessionsObject:)
    @NSManaged public func addToSessions(_ value: ProjectSession)

    @objc(removeSessionsObject:)
    @NSManaged public func removeFromSessions(_ value: ProjectSession)

    @objc(addSessions:)
    @NSManaged public func addToSessions(_ values: NSSet)

    @objc(removeSessions:)
    @NSManaged public func removeFromSessions(_ values: NSSet)
}
