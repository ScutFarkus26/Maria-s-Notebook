import Foundation
import CoreData

@objc(CDSupply)
public class CDSupply: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var location: String
    @NSManaged public var currentQuantity: Int64
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Supply", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = ""
        self.categoryRaw = SupplyCategory.other.rawValue
        self.location = ""
        self.currentQuantity = 0
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Enums

extension CDSupply {

}

// MARK: - Computed Properties

extension CDSupply {
    /// Computed property for category enum
    var category: SupplyCategory {
        get { SupplyCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
