import Foundation
import CoreData

@objc(CDSupplyTransaction)
public class CDSupplyTransaction: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var supplyID: String
    @NSManaged public var date: Date?
    @NSManaged public var quantityChange: Int64
    @NSManaged public var reason: String

    @NSManaged public var supply: CDSupply?
}
