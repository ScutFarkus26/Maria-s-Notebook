import Foundation
import CoreData

/// One line of a staple's history: a level change ("Low · Ana", "Out",
/// "Restocked", `quantityChange` 0) or a counted change with its reason.
/// Written by `RestockService`; in the classroom share with its staple.
@objc(CDSupplyTransaction)
nonisolated public class CDSupplyTransaction: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var supplyID: String
    @NSManaged public var date: Date?
    @NSManaged public var quantityChange: Int64
    @NSManaged public var reason: String

    @NSManaged public var supply: CDSupply?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SupplyTransaction", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.supplyID = ""
        self.reason = ""
    }
}
