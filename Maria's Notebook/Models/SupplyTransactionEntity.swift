import Foundation
import CoreData

@objc(SupplyTransaction)
public class CDSupplyTransaction: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var supplyID: String
    @NSManaged public var date: Date?
    @NSManaged public var quantityChange: Int64
    @NSManaged public var reason: String

    // MARK: - Relationships
    @NSManaged public var supply: CDSupply?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SupplyTransaction", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.supplyID = ""
        self.date = Date()
        self.quantityChange = 0
        self.reason = ""
    }
}
