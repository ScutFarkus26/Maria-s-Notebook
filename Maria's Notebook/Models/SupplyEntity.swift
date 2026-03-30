import Foundation
import CoreData

@objc(Supply)
public class CDSupply: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var location: String
    @NSManaged public var currentQuantity: Int64
    @NSManaged public var minimumThreshold: Int64
    @NSManaged public var reorderAmount: Int64
    @NSManaged public var unit: String
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var isOnOrder: Bool
    @NSManaged public var orderedQuantity: Int64
    @NSManaged public var orderDate: Date?

    // MARK: - Relationships
    @NSManaged public var transactions: NSSet?

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
        self.minimumThreshold = 0
        self.reorderAmount = 0
        self.unit = "items"
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isOnOrder = false
        self.orderedQuantity = 0
        self.orderDate = nil
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

    /// Computed status based on current quantity vs threshold
    var status: SupplyStatus {
        if currentQuantity <= 0 {
            return .outOfStock
        } else if currentQuantity <= minimumThreshold / 2 {
            return .critical
        } else if currentQuantity <= minimumThreshold {
            return .low
        } else {
            return .healthy
        }
    }

    /// Whether this supply needs to be reordered
    var needsReorder: Bool {
        currentQuantity <= minimumThreshold
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDSupply {
    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: CDSupplyTransaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: CDSupplyTransaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)
}
