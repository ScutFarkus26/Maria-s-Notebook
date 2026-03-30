import Foundation
import CoreData

@objc(SampleWorkStepEntity)
public class SampleWorkStepEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var instructions: String
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var sampleWork: SampleWorkEntity?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SampleWorkStep", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.orderIndex = 0
        self.instructions = ""
        self.createdAt = Date()
    }
}
