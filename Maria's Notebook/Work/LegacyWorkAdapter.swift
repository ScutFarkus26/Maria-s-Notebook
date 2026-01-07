import Foundation
import SwiftData

/// Centralized adapter for mapping legacy WorkContract to WorkModel.
/// Provides read-only access to WorkContract and centralized mapping logic.
/// WorkContract is read-only for legacy data only; all mutations use WorkModel.
struct LegacyWorkAdapter {
    let modelContext: ModelContext
    
    /// Fetch all WorkModel records.
    /// This should be called once per refresh scope and the results cached.
    /// - Returns: Array of all WorkModel records
    /// - Throws: SwiftData fetch errors
    func fetchAllWorkModels() throws -> [WorkModel] {
        let descriptor = FetchDescriptor<WorkModel>()
        return try modelContext.fetch(descriptor)
    }
    
    /// Build a dictionary mapping legacy contract IDs to WorkModel instances.
    /// This uses the legacyContractID field on WorkModel to match with WorkContract.id.
    /// - Parameter workModels: Array of WorkModel instances (typically from fetchAllWorkModels())
    /// - Returns: Dictionary mapping WorkContract.id (UUID) to corresponding WorkModel
    func workModelsByLegacyContractID(workModels: [WorkModel]) -> [UUID: WorkModel] {
        Dictionary(uniqueKeysWithValues: workModels.compactMap { work in
            guard let contractID = work.legacyContractID else { return nil }
            return (contractID, work)
        })
    }
    
    /// Resolve a WorkModel for a given legacy WorkContract.
    /// - Parameters:
    ///   - contract: The legacy WorkContract to resolve
    ///   - map: Dictionary mapping contract IDs to WorkModels (from workModelsByLegacyContractID)
    /// - Returns: The corresponding WorkModel if found, nil otherwise
    func resolveWorkModel(forLegacyContract contract: WorkContract, map: [UUID: WorkModel]) -> WorkModel? {
        return map[contract.id]
    }
    
    /// Fetch all WorkContract records (for backward compatibility).
    /// This should be used sparingly and only when necessary for legacy UI.
    /// No SwiftData predicates are used - fetches all and filters in memory.
    /// - Returns: Array of all WorkContract records
    func fetchAllWorkContracts() -> [WorkContract] {
        let descriptor = FetchDescriptor<WorkContract>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

