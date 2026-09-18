import Foundation
import CoreData

/// Service for managing supply operations
enum SupplyService {

    // MARK: - Core Data Methods

    /// Creates a new supply
    static func createSupply(
        name: String,
        category: SupplyCategory,
        location: String,
        currentQuantity: Int,
        notes: String,
        in context: NSManagedObjectContext
    ) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = name
        supply.category = category
        supply.location = location
        supply.currentQuantity = Int64(currentQuantity)
        supply.notes = notes
        supply.createdAt = Date()
        supply.modifiedAt = Date()

        context.safeSave()
        return supply
    }

    /// Updates a supply's quantity directly
    static func updateQuantity(
        for supply: CDSupply,
        newQuantity: Int,
        in context: NSManagedObjectContext
    ) {
        supply.currentQuantity = Int64(newQuantity)
        supply.modifiedAt = Date()
        context.safeSave()
    }

    /// Adds stock to a supply
    static func addStock(
        to supply: CDSupply,
        amount: Int,
        in context: NSManagedObjectContext
    ) {
        supply.currentQuantity += Int64(amount)
        supply.modifiedAt = Date()
        context.safeSave()
    }

    /// Removes stock from a supply
    static func removeStock(
        from supply: CDSupply,
        amount: Int,
        in context: NSManagedObjectContext
    ) {
        supply.currentQuantity = max(0, supply.currentQuantity - Int64(amount))
        supply.modifiedAt = Date()
        context.safeSave()
    }

    /// Deletes a supply
    static func deleteSupply(_ supply: CDSupply, in context: NSManagedObjectContext) {
        context.delete(supply)
        context.safeSave()
    }
}
