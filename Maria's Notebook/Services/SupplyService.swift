import Foundation
import CoreData
import SwiftData

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
                ($0.name ?? "").lowercased().contains(searchLower) ||
                ($0.location ?? "").lowercased().contains(searchLower) ||
                ($0.notes ?? "").lowercased().contains(searchLower)
            }
        }

        return filtered
    }

    /// Fetches supplies that need to be reordered
    @MainActor
    static func fetchLowStockSupplies(in context: NSManagedObjectContext) -> [CDSupply] {
        let request = CDFetchRequest(CDSupply.self)
        request.sortDescriptors = [NSSortDescriptor(key: "currentQuantity", ascending: true)]

        let supplies = context.safeFetch(request)
        return supplies.filter(\.needsReorder)
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

    /// Gets summary statistics for supplies
    @MainActor
    static func getSupplyStats(in context: NSManagedObjectContext) -> SupplyStats {
        let request = CDFetchRequest(CDSupply.self)
        let supplies = context.safeFetch(request)

        let total = supplies.count
        let lowStock = supplies.filter { $0.status == .low || $0.status == .critical }.count
        let outOfStock = supplies.filter { $0.status == .outOfStock }.count
        let needsReorder = supplies.filter(\.needsReorder).count
        let onOrder = supplies.filter(\.isOnOrder).count

        return SupplyStats(
            totalSupplies: total,
            lowStock: lowStock,
            outOfStock: outOfStock,
            needsReorder: needsReorder,
            onOrder: onOrder
        )
    }

    /// Creates a new supply
    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func createSupply(
        name: String,
        category: SupplyCategory,
        location: String,
        currentQuantity: Int,
        minimumThreshold: Int,
        reorderAmount: Int,
        unit: String,
        notes: String,
        in context: NSManagedObjectContext
    ) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = name
        supply.category = category
        supply.location = location
        supply.currentQuantity = Int64(currentQuantity)
        supply.minimumThreshold = Int64(minimumThreshold)
        supply.reorderAmount = Int64(reorderAmount)
        supply.unit = unit
        supply.notes = notes
        supply.createdAt = Date()
        supply.modifiedAt = Date()

        // Record initial stock as a transaction
        if currentQuantity > 0 {
            let transaction = CDSupplyTransaction(context: context)
            transaction.id = UUID()
            transaction.supplyID = supply.id?.uuidString ?? ""
            transaction.quantityChange = Int64(currentQuantity)
            transaction.reason = "Initial stock"
            transaction.date = Date()
            transaction.supply = supply
        }

        context.safeSave()
        return supply
    }

    /// Updates a supply's quantity with a transaction record
    @MainActor
    static func updateQuantity(
        for supply: CDSupply,
        newQuantity: Int,
        reason: String,
        in context: NSManagedObjectContext
    ) {
        let change = newQuantity - Int(supply.currentQuantity)
        guard change != 0 else { return }

        adjustQuantity(of: supply, by: change, reason: reason, in: context)
        context.safeSave()
    }

    /// Adds stock to a supply
    @MainActor
    static func addStock(
        to supply: CDSupply,
        amount: Int,
        reason: String = "Restocked",
        in context: NSManagedObjectContext
    ) {
        adjustQuantity(of: supply, by: amount, reason: reason, in: context)
        context.safeSave()
    }

    /// Removes stock from a supply
    @MainActor
    static func removeStock(
        from supply: CDSupply,
        amount: Int,
        reason: String = "Used",
        in context: NSManagedObjectContext
    ) {
        adjustQuantity(of: supply, by: -amount, reason: reason, in: context)
        context.safeSave()
    }

    /// Marks a supply as ordered
    @MainActor
    static func markAsOrdered(
        _ supply: CDSupply,
        quantity: Int,
        in context: NSManagedObjectContext
    ) {
        supply.isOnOrder = true
        supply.orderedQuantity = Int64(quantity)
        supply.orderDate = Date()
        supply.modifiedAt = Date()

        let transaction = CDSupplyTransaction(context: context)
        transaction.supplyID = supply.id?.uuidString ?? ""
        transaction.quantityChange = 0
        transaction.reason = "Ordered \(quantity) \(supply.unit)"
        transaction.supply = supply

        context.safeSave()
    }

    /// Marks a supply order as received and adds stock
    @MainActor
    static func markAsReceived(
        _ supply: CDSupply,
        receivedQuantity: Int,
        in context: NSManagedObjectContext
    ) {
        adjustQuantity(of: supply, by: receivedQuantity, reason: "Order received", in: context)
        supply.isOnOrder = false
        supply.orderedQuantity = 0
        supply.orderDate = nil
        supply.modifiedAt = Date()
        context.safeSave()
    }

    /// Deletes a supply and all its transactions
    @MainActor
    static func deleteSupply(_ supply: CDSupply, in context: NSManagedObjectContext) {
        context.delete(supply)
        context.safeSave()
    }

    /// Fetches recent transactions for a supply
    @MainActor
    static func fetchRecentTransactions(
        for supply: CDSupply,
        limit: Int = 20
    ) -> [CDSupplyTransaction] {
        let transactions = (supply.transactions as? Set<CDSupplyTransaction>) ?? []
        return Array(
            transactions
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                .prefix(limit)
        )
    }

    // MARK: - Private Helpers

    /// Adjusts a supply's quantity and records a transaction
    private static func adjustQuantity(
        of supply: CDSupply,
        by change: Int,
        reason: String,
        in context: NSManagedObjectContext
    ) {
        supply.currentQuantity += Int64(change)
        supply.modifiedAt = Date()

        let transaction = CDSupplyTransaction(context: context)
        transaction.supplyID = supply.id?.uuidString ?? ""
        transaction.quantityChange = Int64(change)
        transaction.reason = reason
        transaction.supply = supply
    }

    // MARK: - Deprecated SwiftData Methods

    /// Fetches all supplies, optionally filtered by category
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func fetchSupplies(
        in context: ModelContext,
        category: SupplyCategory? = nil,
        searchText: String = ""
    ) -> [Supply] {
        let descriptor = FetchDescriptor<Supply>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )

        let supplies = context.safeFetch(descriptor)

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

    /// Fetches supplies that need to be reordered
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func fetchLowStockSupplies(in context: ModelContext) -> [Supply] {
        let descriptor = FetchDescriptor<Supply>(
            sortBy: [SortDescriptor(\.currentQuantity, order: .forward)]
        )

        let supplies = context.safeFetch(descriptor)
        return supplies.filter(\.needsReorder)
    }

    /// Fetches supplies grouped by category
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func fetchSuppliesGroupedByCategory(
        in context: ModelContext,
        searchText: String = ""
    ) -> [(category: SupplyCategory, supplies: [Supply])] {
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

    /// Gets summary statistics for supplies
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func getSupplyStats(in context: ModelContext) -> SupplyStats {
        let descriptor = FetchDescriptor<Supply>()
        let supplies = context.safeFetch(descriptor)

        let total = supplies.count
        let lowStock = supplies.filter { $0.status == .low || $0.status == .critical }.count
        let outOfStock = supplies.filter { $0.status == .outOfStock }.count
        let needsReorder = supplies.filter(\.needsReorder).count
        let onOrder = supplies.filter(\.isOnOrder).count

        return SupplyStats(
            totalSupplies: total,
            lowStock: lowStock,
            outOfStock: outOfStock,
            needsReorder: needsReorder,
            onOrder: onOrder
        )
    }

    /// Creates a new supply
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func createSupply(
        name: String,
        category: SupplyCategory,
        location: String,
        currentQuantity: Int,
        minimumThreshold: Int,
        reorderAmount: Int,
        unit: String,
        notes: String,
        in context: ModelContext
    ) -> Supply {
        let supply = Supply(
            name: name,
            category: category,
            location: location,
            currentQuantity: currentQuantity,
            minimumThreshold: minimumThreshold,
            reorderAmount: reorderAmount,
            unit: unit,
            notes: notes
        )
        context.insert(supply)

        // Record initial stock as a transaction
        if currentQuantity > 0 {
            let transaction = SupplyTransaction(
                supplyID: supply.id.uuidString,
                quantityChange: currentQuantity,
                reason: "Initial stock",
                supply: supply
            )
            context.insert(transaction)
        }

        context.safeSave()
        return supply
    }

    /// Updates a supply's quantity with a transaction record
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func updateQuantity(
        for supply: Supply,
        newQuantity: Int,
        reason: String,
        in context: ModelContext
    ) {
        let change = newQuantity - supply.currentQuantity
        guard change != 0 else { return }

        supply.adjustQuantity(by: change, reason: reason, in: context)
        context.safeSave()
    }

    /// Adds stock to a supply
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func addStock(
        to supply: Supply,
        amount: Int,
        reason: String = "Restocked",
        in context: ModelContext
    ) {
        supply.adjustQuantity(by: amount, reason: reason, in: context)
        context.safeSave()
    }

    /// Removes stock from a supply
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func removeStock(
        from supply: Supply,
        amount: Int,
        reason: String = "Used",
        in context: ModelContext
    ) {
        supply.adjustQuantity(by: -amount, reason: reason, in: context)
        context.safeSave()
    }

    /// Marks a supply as ordered
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func markAsOrdered(
        _ supply: Supply,
        quantity: Int,
        in context: ModelContext
    ) {
        supply.isOnOrder = true
        supply.orderedQuantity = quantity
        supply.orderDate = Date()
        supply.modifiedAt = Date()

        let transaction = SupplyTransaction(
            supplyID: supply.id.uuidString,
            quantityChange: 0,
            reason: "Ordered \(quantity) \(supply.unit)",
            supply: supply
        )
        context.insert(transaction)
        context.safeSave()
    }

    /// Marks a supply order as received and adds stock
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func markAsReceived(
        _ supply: Supply,
        receivedQuantity: Int,
        in context: ModelContext
    ) {
        supply.adjustQuantity(by: receivedQuantity, reason: "Order received", in: context)
        supply.isOnOrder = false
        supply.orderedQuantity = 0
        supply.orderDate = nil
        supply.modifiedAt = Date()
        context.safeSave()
    }

    /// Deletes a supply and all its transactions
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func deleteSupply(_ supply: Supply, in context: ModelContext) {
        context.delete(supply)
        context.safeSave()
    }

    /// Fetches recent transactions for a supply
    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func fetchRecentTransactions(
        for supply: Supply,
        limit: Int = 20
    ) -> [SupplyTransaction] {
        let transactions = supply.transactions ?? []
        return Array(
            transactions
                .sorted { $0.date > $1.date }
                .prefix(limit)
        )
    }
}

/// Statistics about the supply inventory
struct SupplyStats {
    let totalSupplies: Int
    let lowStock: Int
    let outOfStock: Int
    let needsReorder: Int
    let onOrder: Int
}
