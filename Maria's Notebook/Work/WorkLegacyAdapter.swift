import Foundation
import SwiftData

/// Legacy adapter utility for mapping WorkContract IDs to WorkModel instances.
/// This provides a safe, performant way to access WorkModel data for legacy WorkContract references.
@MainActor
struct WorkLegacyAdapter {
    let modelContext: ModelContext
    
    /// Cached mapping of legacy contract IDs to WorkModel instances.
    /// Built once per adapter instance and reused for the scope of the adapter.
    private let workModelByLegacyContractID: [UUID: WorkModel]
    
    /// Initialize the adapter and build the legacy contract ID mapping.
    /// This fetches all WorkModels once and indexes them by legacyContractID.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // Fetch all WorkModels once
        let allWorkModels = (try? modelContext.fetch(FetchDescriptor<WorkModel>())) ?? []
        
        // Build dictionary indexed by legacyContractID
        var mapping: [UUID: WorkModel] = [:]
        for work in allWorkModels {
            if let legacyID = work.legacyContractID {
                mapping[legacyID] = work
            }
        }
        self.workModelByLegacyContractID = mapping
    }
    
    /// Find the WorkModel that corresponds to a legacy WorkContract ID.
    /// Returns nil if no WorkModel has this legacyContractID.
    func workModel(forLegacyContractID contractID: UUID) -> WorkModel? {
        return workModelByLegacyContractID[contractID]
    }
    
    /// Check if a legacy contract ID has a corresponding WorkModel.
    func hasWorkModel(forLegacyContractID contractID: UUID) -> Bool {
        return workModelByLegacyContractID[contractID] != nil
    }
}

