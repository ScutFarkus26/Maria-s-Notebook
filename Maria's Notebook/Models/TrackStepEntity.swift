import Foundation
import CoreData

@objc(TrackStepEntity)
public class CDTrackStepEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var lessonTemplateID: UUID?
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var track: CDTrackEntity?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TrackStep", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.orderIndex = 0
        self.lessonTemplateID = nil
        self.createdAt = Date()
    }
}
