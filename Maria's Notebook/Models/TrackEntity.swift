import Foundation
import CoreData

@objc(TrackEntity)
public class CDTrackEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var enrollments: NSSet?
    @NSManaged public var groupTrack: CDGroupTrackEntity?
    @NSManaged public var steps: NSSet?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Track", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.createdAt = Date()
    }
}

// MARK: - Generated Accessors for steps
extension CDTrackEntity {
    @objc(addStepsObject:)
    @NSManaged public func addToSteps(_ value: CDTrackStepEntity)

    @objc(removeStepsObject:)
    @NSManaged public func removeFromSteps(_ value: CDTrackStepEntity)

    @objc(addSteps:)
    @NSManaged public func addToSteps(_ values: NSSet)

    @objc(removeSteps:)
    @NSManaged public func removeFromSteps(_ values: NSSet)
}
