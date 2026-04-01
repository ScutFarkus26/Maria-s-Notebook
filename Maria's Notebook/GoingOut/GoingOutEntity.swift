import Foundation
import CoreData

@objc(CDGoingOut)
public class CDGoingOut: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var title: String
    @NSManaged public var purpose: String
    @NSManaged public var destination: String
    @NSManaged public var proposedDate: Date?
    @NSManaged public var actualDate: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var studentIDs: NSObject?  // Transformable [String]
    @NSManaged public var curriculumLinkIDs: String
    @NSManaged public var permissionStatusRaw: String
    @NSManaged public var notes: String
    @NSManaged public var followUpWork: String
    @NSManaged public var supervisorName: String

    // MARK: - Relationships
    @NSManaged public var checklistItems: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "GoingOut", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.title = ""
        self.purpose = ""
        self.destination = ""
        self.proposedDate = nil
        self.actualDate = nil
        self.statusRaw = GoingOutStatus.proposed.rawValue
        self.studentIDs = [] as NSArray
        self.curriculumLinkIDs = ""
        self.permissionStatusRaw = PermissionStatus.pending.rawValue
        self.notes = ""
        self.followUpWork = ""
        self.supervisorName = ""
    }
}

// MARK: - Enums

extension CDGoingOut {

}

// MARK: - Computed Properties

extension CDGoingOut {
    var status: GoingOutStatus {
        get { GoingOutStatus(rawValue: statusRaw) ?? .proposed }
        set { statusRaw = newValue.rawValue; modifiedAt = Date() }
    }

    var permissionStatus: PermissionStatus {
        get { PermissionStatus(rawValue: permissionStatusRaw) ?? .pending }
        set { permissionStatusRaw = newValue.rawValue; modifiedAt = Date() }
    }

    /// Access studentIDs as a Swift [String] array
    var studentIDsArray: [String] {
        get { (studentIDs as? [String]) ?? [] }
        set { studentIDs = newValue as NSArray }
    }

    var studentUUIDs: [UUID] {
        get { studentIDsArray.compactMap { UUID(uuidString: $0) } }
        set { studentIDsArray = newValue.map(\.uuidString) }
    }

    var curriculumLinkUUIDs: [UUID] {
        get {
            curriculumLinkIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            curriculumLinkIDs = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    var sortedChecklistItems: [CDGoingOutChecklistItem] {
        ((checklistItems as? Set<CDGoingOutChecklistItem>).map(Array.init) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Cross-store inverse: fetches Notes whose goingOutID matches this going out.
    var observationNotes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "goingOutID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDGoingOut {
    @objc(addChecklistItemsObject:)
    @NSManaged public func addToChecklistItems(_ value: CDGoingOutChecklistItem)

    @objc(removeChecklistItemsObject:)
    @NSManaged public func removeFromChecklistItems(_ value: CDGoingOutChecklistItem)

    @objc(addChecklistItems:)
    @NSManaged public func addToChecklistItems(_ values: NSSet)

    @objc(removeChecklistItems:)
    @NSManaged public func removeFromChecklistItems(_ values: NSSet)

}
