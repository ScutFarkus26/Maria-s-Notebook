import CoreData

// The notebook gives its entities `Identifiable` in `Models/CoreDataIdentifiable.swift`,
// which the Assistant doesn't compile; Restock's sheets need these two.
nonisolated extension CDSupply: Identifiable {}
nonisolated extension CDOrderItem: Identifiable {}
