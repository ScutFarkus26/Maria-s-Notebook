import Foundation
import CoreData

/// Service for managing procedure operations
enum ProcedureService {

    // MARK: - Core Data Methods

    /// Fetches all procedures, optionally filtered by category
    @MainActor
    static func fetchProcedures(
        in context: NSManagedObjectContext,
        category: ProcedureCategory? = nil,
        searchText: String = ""
    ) -> [CDProcedure] {
        let request = CDFetchRequest(CDProcedure.self)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]

        let procedures = context.safeFetch(request)

        var filtered = procedures

        // Filter by category if specified
        if let category {
            filtered = filtered.filter { $0.category == category }
        }

        // Filter by search text if provided
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter {
                $0.title.lowercased().contains(searchLower) ||
                $0.summary.lowercased().contains(searchLower) ||
                $0.content.lowercased().contains(searchLower)
            }
        }

        return filtered
    }

    /// Fetches procedures grouped by category
    @MainActor
    static func fetchProceduresGroupedByCategory(
        in context: NSManagedObjectContext,
        searchText: String = ""
    ) -> [(category: ProcedureCategory, procedures: [CDProcedure])] {
        let allProcedures = fetchProcedures(in: context, searchText: searchText)

        // Group by category
        let grouped = Dictionary(grouping: allProcedures) { $0.category }

        // Sort categories by their display order and filter out empty ones
        return ProcedureCategory.allCases.compactMap { category in
            guard let procedures = grouped[category], !procedures.isEmpty else {
                return nil
            }
            return (category: category, procedures: procedures)
        }
    }

    /// Gets summary statistics for procedures
    @MainActor
    static func getProcedureStats(in context: NSManagedObjectContext) -> ProcedureStats {
        let request = CDFetchRequest(CDProcedure.self)
        let procedures = context.safeFetch(request)

        let total = procedures.count
        let byCategory = Dictionary(grouping: procedures) { $0.category }
            .mapValues { $0.count }

        // Find recently updated (within last 30 days)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentlyUpdated = procedures.filter { ($0.modifiedAt ?? .distantPast) >= thirtyDaysAgo }.count

        return ProcedureStats(
            totalProcedures: total,
            byCategory: byCategory,
            recentlyUpdated: recentlyUpdated
        )
    }

    /// Creates a new procedure
    @MainActor @discardableResult
    // swiftlint:disable:next function_parameter_count
    static func createProcedure(
        title: String,
        summary: String,
        content: String,
        category: ProcedureCategory,
        icon: String,
        relatedProcedureIDs: [String],
        in context: NSManagedObjectContext
    ) -> CDProcedure {
        let procedure = CDProcedure(context: context)
        procedure.id = UUID()
        procedure.title = title
        procedure.summary = summary
        procedure.content = content
        procedure.category = category
        procedure.icon = icon
        procedure.relatedProcedureIDs = relatedProcedureIDs
        procedure.createdAt = Date()
        procedure.modifiedAt = Date()
        context.safeSave()
        return procedure
    }

    /// Updates an existing procedure
    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func updateProcedure(
        _ procedure: CDProcedure,
        title: String,
        summary: String,
        content: String,
        category: ProcedureCategory,
        icon: String,
        relatedProcedureIDs: [String],
        in context: NSManagedObjectContext
    ) {
        procedure.title = title
        procedure.summary = summary
        procedure.content = content
        procedure.category = category
        procedure.icon = icon
        procedure.relatedProcedureIDs = relatedProcedureIDs
        procedure.modifiedAt = Date()
        context.safeSave()
    }

    /// Deletes a procedure
    @MainActor
    static func deleteProcedure(_ procedure: CDProcedure, in context: NSManagedObjectContext) {
        context.delete(procedure)
        context.safeSave()
    }

    /// Fetches a procedure by ID
    @MainActor
    static func fetchProcedure(byID id: UUID, in context: NSManagedObjectContext) -> CDProcedure? {
        let request = CDFetchRequest(CDProcedure.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// Fetches related procedures for a given procedure
    @MainActor
    static func fetchRelatedProcedures(for procedure: CDProcedure, in context: NSManagedObjectContext) -> [CDProcedure] {
        let relatedIDs = procedure.relatedProcedureIDs
        guard !relatedIDs.isEmpty else { return [] }

        let request = CDFetchRequest(CDProcedure.self)
        let allProcedures = context.safeFetch(request)

        return allProcedures.filter { proc in
            guard let procID = proc.id else { return false }
            return relatedIDs.contains(procID.uuidString)
        }
    }

    // Deprecated SwiftData methods removed - use Core Data overloads.
}

/// Statistics about procedures
struct ProcedureStats {
    let totalProcedures: Int
    let byCategory: [ProcedureCategory: Int]
    let recentlyUpdated: Int
}
