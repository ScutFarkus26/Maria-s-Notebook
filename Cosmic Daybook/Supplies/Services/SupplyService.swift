import Foundation
import CoreData

/// Service for managing supply operations
enum SupplyService {

    // MARK: - Core Data Methods

    /// The fields the Add Supply sheet collects before a row exists.
    struct SupplyDraft {
        let name: String
        let category: SupplyCategory
        let location: String
        let currentQuantity: Int
        let notes: String
    }

    /// Creates a new supply
    static func createSupply(_ draft: SupplyDraft, in context: NSManagedObjectContext) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = draft.name
        supply.category = draft.category
        supply.location = draft.location
        supply.currentQuantity = Int64(draft.currentQuantity)
        supply.notes = draft.notes
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
