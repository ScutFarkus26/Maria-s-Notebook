import Foundation
import CoreData

/// Service for managing supply operations
enum SupplyService {

    // MARK: - Core Data Methods

    /// Fetches all supplies, optionally filtered by category
    @MainActor
    static func fetchSupplies(
        in context: NSManagedObjectContext,
        category: SupplyCategory? = nil,
        searchText: String = ""
    ) -> [CDSupply] {
        let request = CDFetchRequest(CDSupply.self)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        let supplies = context.safeFetch(request)

        var filtered = supplies

        // Filter by category if specified
        if let category {
            filtered = filtered.filter { $0.category == category }
        }

        // Filter by search text if provided
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter {
                $0.name.lowercased().contains(searchLower) ||
                $0.location.lowercased().contains(searchLower) ||
                $0.notes.lowercased().contains(searchLower)
            }
        }

        return filtered
    }

    /// Fetches supplies grouped by category
    @MainActor
    static func fetchSuppliesGroupedByCategory(
        in context: NSManagedObjectContext,
        searchText: String = ""
    ) -> [(category: SupplyCategory, supplies: [CDSupply])] {
        let allSupplies = fetchSupplies(in: context, searchText: searchText)

        // Group by category
        let grouped = Dictionary(grouping: allSupplies) { $0.category }

        // Sort categories by their display order and filter out empty ones
        return SupplyCategory.allCases.compactMap { category in
            guard let supplies = grouped[category], !supplies.isEmpty else {
                return nil
            }
            return (category: category, supplies: supplies)
        }
    }

    /// Creates a new supply
    @MainActor
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
    @MainActor
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
    @MainActor
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
    @MainActor
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
    @MainActor
    static func deleteSupply(_ supply: CDSupply, in context: NSManagedObjectContext) {
        context.delete(supply)
        context.safeSave()
    }
}
