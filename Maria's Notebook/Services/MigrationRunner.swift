import SwiftData
import Foundation

enum MigrationRunner {
    static func runIfNeeded(context: ModelContext) {
        let key = "MigrationRunner.v1.practiceFollowUpBackfill"
        // Disabled: Do not fetch or mutate WorkModel at startup.
        // Mark as done to avoid reruns while retaining compatibility flags.
        MigrationFlag.markComplete(key: key)
        
        // Migrate WorkContracts to WorkModels (idempotent - safe to run multiple times)
        migrateWorkContractsToWorkModels(context: context)
    }
    
    /// Migrate WorkContract records to WorkModel records.
    /// Idempotent: only migrates contracts that don't already have corresponding WorkModels.
    /// Safe to run multiple times - checks for existing WorkModels by legacyContractID.
    /// - Parameter context: The ModelContext to use for the migration
    static func migrateWorkContractsToWorkModels(context: ModelContext) {
        // Fetch all WorkContract records
        let contracts = context.safeFetch(FetchDescriptor<WorkContract>())
        
        #if DEBUG
        // Pre-migration check: Skip if already migrated
        let workModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let legacyWorkModels = workModels.filter { $0.legacyContractID != nil }
        let workContractsCount = contracts.count
        let legacyWorkModelsCount = legacyWorkModels.count
        
        // If already migrated (legacyWorkModelsCount >= workContractsCount and workContractsCount > 0), skip
        if legacyWorkModelsCount >= workContractsCount && workContractsCount > 0 {
            print("WorkContract→WorkModel migration SKIPPED (already migrated) legacyWorkModels=\(legacyWorkModelsCount) contracts=\(workContractsCount)")
            verifyWorkMigration(context: context)
            return
        }
        
        if contracts.count > 0 {
            print("WARNING: WorkContract read-path still active in MigrationRunner.migrateWorkContractsToWorkModels count=\(contracts.count)")
        }
        #endif
        
        print("WorkContract→WorkModel migration START")
        
        var scanned = 0
        var created = 0
        var skipped = 0
        
        guard !contracts.isEmpty else {
            print("WorkContract→WorkModel migration END scanned=\(scanned) created=\(created) skipped=\(skipped)")
            #if DEBUG
            verifyWorkMigration(context: context)
            #endif
            return
        }
        
        // Fetch all WorkModel records and build a set of existing legacyContractID values
        let workModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let existingLegacyContractIDs = Set(workModels.compactMap { $0.legacyContractID })
        
        // For each WorkContract that doesn't already exist as a WorkModel, create a WorkModel
        for contract in contracts {
            scanned += 1
            
            // Skip if this contract already has a corresponding WorkModel
            guard !existingLegacyContractIDs.contains(contract.id) else {
                skipped += 1
                continue
            }
            
            // Create WorkModel using the helper (this already sets legacyContractID and creates participants)
            let workModel = WorkModel.from(contract: contract, in: context)
            
            // Insert into context
            context.insert(workModel)
            created += 1
        }
        
        // Save all changes
        if created > 0 {
            do {
                try context.save()
            } catch {
                print("MigrationRunner: Failed to save migrated WorkModels: \(error.localizedDescription)")
                print("WorkContract→WorkModel migration END scanned=\(scanned) created=\(created) skipped=\(skipped)")
                #if DEBUG
                verifyWorkMigration(context: context)
                #endif
                return
            }
        }
        
        // Print summary (always printed, even when scanned=0)
        print("WorkContract→WorkModel migration END scanned=\(scanned) created=\(created) skipped=\(skipped)")
        
        #if DEBUG
        verifyWorkMigration(context: context)
        #endif
    }
    
    #if DEBUG
    /// Verification method that prints statistics about WorkContract and WorkModel migration state.
    /// - Parameter context: The ModelContext to use for the verification
    static func verifyWorkMigration(context: ModelContext) {
        let contracts = context.safeFetch(FetchDescriptor<WorkContract>())
        let workModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let legacyWorkModels = workModels.filter { $0.legacyContractID != nil }
        
        print("WorkContract→WorkModel migration verification: WorkContract=\(contracts.count) WorkModel=\(workModels.count) WorkModel(legacyContractID!=nil)=\(legacyWorkModels.count)")
    }
    #endif
}
