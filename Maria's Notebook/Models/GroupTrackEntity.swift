import Foundation
import CoreData

@objc(GroupTrackEntity)
public class CDGroupTrackEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var subject: String
    @NSManaged public var group: String
    @NSManaged public var isSequential: Bool
    @NSManaged public var isExplicitlyDisabled: Bool
    @NSManaged public var createdAt: Date?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "GroupTrack", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.subject = ""
        self.group = ""
        self.isSequential = true
        self.isExplicitlyDisabled = false
        self.createdAt = Date()
    }
}

// MARK: - Computed Properties
extension CDGroupTrackEntity {
    /// Unique identifier for this (subject, group) combination
    var groupKey: String {
        "\(subject)|\(group)"
    }
}
