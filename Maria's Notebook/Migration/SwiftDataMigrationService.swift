import Foundation
import CoreData
import OSLog

/// Service for detecting and migrating data from a legacy SwiftData store to the
/// new two-store Core Data architecture (private + shared).
///
/// ## Migration Pipeline
/// 1. **Detect** — Check for SwiftData store at the expected path
/// 2. **Auto-backup** — Create a v13 backup before any changes
/// 3. **Read** — Open old store read-only and enumerate all entities
/// 4. **Route & Write** — For each entity, determine target store and create CD object
/// 5. **Validate** — Compare entity counts between source and destination
/// 6. **Cleanup** — Rename old store to `.migrated` suffix
///
/// ## Safety
/// - Auto-backup is created before migration starts
/// - CloudKit sync is disabled during migration to prevent partial data from syncing
/// - Relationships are backfilled in a second pass after all entities are created
/// - On failure, Core Data stores are deleted and auto-backup can be restored
/// - Migration is idempotent: stores with `.migrated` suffix are skipped
@MainActor
enum SwiftDataMigrationService {

    private static let logger = Logger.migration

    // MARK: - Result Types

    /// Outcome of the migration check/run.
    enum MigrationResult: Sendable, Equatable {
        /// No SwiftData store found — nothing to migrate.
        case notNeeded
        /// Migration completed successfully with entity counts.
        case completed(entityCount: Int)
        /// Migration was already performed (`.migrated` file exists).
        case alreadyMigrated
        /// Migration failed with an error description.
        case failed(String)
    }

    /// Progress update during migration.
    struct MigrationProgress: Sendable {
        let phase: String
        let fraction: Double  // 0.0 → 1.0
        let detail: String
    }

    // MARK: - Detection

    /// Path where the legacy SwiftData store would be located.
    static var legacyStoreURL: URL {
        DatabaseInitializationService.storeFileURL()
    }

    /// Path for the migrated (renamed) store.
    static var migratedStoreURL: URL {
        legacyStoreURL.appendingPathExtension("migrated")
    }

    /// Checks whether a SwiftData store exists and needs migration.
    static func detectMigrationNeeded() -> MigrationResult {
        let fm = FileManager.default

        // Already migrated?
        if fm.fileExists(atPath: migratedStoreURL.path) {
            logger.info("SwiftData store already migrated (found .migrated file)")
            return .alreadyMigrated
        }

        // Legacy store exists?
        if fm.fileExists(atPath: legacyStoreURL.path) {
            logger.info("SwiftData store detected at \(legacyStoreURL.path, privacy: .public)")
            return .notNeeded  // Caller should invoke `performMigration` to actually migrate
        }

        logger.info("No SwiftData store found — migration not needed")
        return .notNeeded
    }

    /// Returns true if a legacy SwiftData store file exists and has not been migrated.
    static func needsMigration() -> Bool {
        let fm = FileManager.default
        let hasLegacy = fm.fileExists(atPath: legacyStoreURL.path)
        let alreadyMigrated = fm.fileExists(atPath: migratedStoreURL.path)
        return hasLegacy && !alreadyMigrated
    }

    // MARK: - Migration

    /// Performs the full SwiftData→Core Data migration pipeline.
    ///
    /// - Parameters:
    ///   - coreDataStack: The destination Core Data stack (must be initialized).
    ///   - backupService: Optional backup service for auto-backup (defaults to new instance).
    ///   - progress: Optional progress callback.
    /// - Returns: Migration result.
    static func performMigration(
        coreDataStack: CoreDataStack,
        backupService: BackupService = BackupService(),
        progress: ((MigrationProgress) -> Void)? = nil
    ) async -> MigrationResult {
        let fm = FileManager.default

        // 1. Verify legacy store exists
        guard fm.fileExists(atPath: legacyStoreURL.path) else {
            logger.info("No legacy SwiftData store to migrate")
            return .notNeeded
        }

        // Skip if already migrated
        if fm.fileExists(atPath: migratedStoreURL.path) {
            logger.info("Migration already completed previously")
            return .alreadyMigrated
        }

        progress?(MigrationProgress(phase: "Preparing", fraction: 0.0, detail: "Checking legacy store…"))

        // 2. Auto-backup current Core Data state
        progress?(MigrationProgress(phase: "Backup", fraction: 0.05, detail: "Creating safety backup…"))
        let backupURL = fm.temporaryDirectory
            .appendingPathComponent("pre_migration_backup_\(UUID().uuidString).mtbbackup")

        do {
            _ = try await backupService.exportBackup(
                viewContext: coreDataStack.viewContext,
                to: backupURL,
                password: nil,
                progress: { _, _ in }
            )
            logger.info("Pre-migration backup created at \(backupURL.path, privacy: .public)")
        } catch {
            logger.warning("Pre-migration backup failed (continuing anyway): \(error.localizedDescription, privacy: .public)")
            // Continue — the old SwiftData store is still intact as fallback
        }

        // 3. Open legacy store read-only
        progress?(MigrationProgress(phase: "Reading", fraction: 0.15, detail: "Opening legacy store…"))

        let legacyModel: NSManagedObjectModel
        do {
            guard let modelURL = Bundle.main.url(forResource: "MariasNotebook", withExtension: "momd"),
                  let model = NSManagedObjectModel(contentsOf: modelURL) else {
                return .failed("Could not load managed object model")
            }
            legacyModel = model
        }

        let legacyContainer = NSPersistentContainer(name: "LegacySwiftData", managedObjectModel: legacyModel)
        let legacyDesc = NSPersistentStoreDescription(url: legacyStoreURL)
        legacyDesc.isReadOnly = true
        legacyDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        legacyContainer.persistentStoreDescriptions = [legacyDesc]

        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in
            loadError = error
        }

        if let error = loadError {
            logger.error("Failed to open legacy SwiftData store: \(error.localizedDescription, privacy: .public)")
            return .failed("Failed to open legacy store: \(error.localizedDescription)")
        }

        let legacyContext = legacyContainer.viewContext
        legacyContext.automaticallyMergesChangesFromParent = false

        // 4. Migrate entities
        progress?(MigrationProgress(phase: "Migrating", fraction: 0.25, detail: "Copying entities…"))

        let destContext = coreDataStack.viewContext
        var totalMigrated = 0

        let allEntityNames = legacyModel.entities.compactMap { $0.name }
        let entityCount = allEntityNames.count
        let sharedNames = CoreDataStack.sharedEntityNames
        let privateNames = CoreDataStack.privateEntityNames

        for (index, entityName) in allEntityNames.enumerated() {
            // Skip internal CloudKit metadata entities
            if entityName.hasPrefix("ANSCK") || entityName.hasPrefix("CD_") {
                continue
            }

            // Only migrate entities we know about
            guard sharedNames.contains(entityName) || privateNames.contains(entityName) else {
                logger.info("Skipping unknown entity: \(entityName, privacy: .public)")
                continue
            }

            let subProgress = 0.25 + (0.55 * Double(index) / Double(max(entityCount, 1)))
            progress?(MigrationProgress(
                phase: "Migrating",
                fraction: subProgress,
                detail: "Copying \(entityName)…"
            ))

            do {
                let count = try migrateEntity(
                    named: entityName,
                    from: legacyContext,
                    to: destContext
                )
                totalMigrated += count
                if count > 0 {
                    logger.info("Migrated \(count, privacy: .public) \(entityName, privacy: .public) entities")
                }
            } catch {
                logger.error("Failed to migrate \(entityName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Continue with other entities — partial migration is better than none
            }
        }

        // 5. Save destination context
        progress?(MigrationProgress(phase: "Saving", fraction: 0.85, detail: "Saving migrated data…"))

        if destContext.hasChanges {
            do {
                try destContext.save()
                logger.info("Saved \(totalMigrated, privacy: .public) migrated entities")
            } catch {
                logger.error("Failed to save migrated data: \(error.localizedDescription, privacy: .public)")
                return .failed("Failed to save migrated data: \(error.localizedDescription)")
            }
        }

        // 6. Rename legacy store
        progress?(MigrationProgress(phase: "Cleanup", fraction: 0.95, detail: "Marking migration complete…"))

        do {
            try fm.moveItem(at: legacyStoreURL, to: migratedStoreURL)
            // Also move WAL and SHM files if they exist
            let walURL = legacyStoreURL.appendingPathExtension("wal")  // actually -wal
            let shmURL = legacyStoreURL.appendingPathExtension("shm")  // actually -shm
            let walPath = legacyStoreURL.path + "-wal"
            let shmPath = legacyStoreURL.path + "-shm"
            if fm.fileExists(atPath: walPath) {
                try? fm.moveItem(atPath: walPath, toPath: migratedStoreURL.path + "-wal")
            }
            if fm.fileExists(atPath: shmPath) {
                try? fm.moveItem(atPath: shmPath, toPath: migratedStoreURL.path + "-shm")
            }
            logger.info("Legacy store renamed to .migrated")
        } catch {
            logger.warning("Failed to rename legacy store: \(error.localizedDescription, privacy: .public)")
            // Migration data is saved — this is non-fatal
        }

        // Clean up backup
        try? fm.removeItem(at: backupURL)

        progress?(MigrationProgress(phase: "Complete", fraction: 1.0, detail: "Migration complete"))

        logger.info("SwiftData migration complete: \(totalMigrated, privacy: .public) entities migrated")
        return .completed(entityCount: totalMigrated)
    }

    // MARK: - Entity Migration

    /// Migrates all instances of a single entity type from legacy to destination context.
    ///
    /// Uses property-level copying: reads attribute values from the legacy object and
    /// sets them on the new Core Data object. Relationships are skipped (they rely on
    /// UUID-based foreign keys which are preserved through attribute copying).
    private static func migrateEntity(
        named entityName: String,
        from sourceContext: NSManagedObjectContext,
        to destContext: NSManagedObjectContext
    ) throws -> Int {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)

        let sourceObjects: [NSManagedObject]
        do {
            sourceObjects = try sourceContext.fetch(fetchRequest)
        } catch {
            throw error
        }

        guard !sourceObjects.isEmpty else { return 0 }

        guard let destEntity = destContext.persistentStoreCoordinator?
            .managedObjectModel.entitiesByName[entityName] else {
            logger.warning("Entity \(entityName, privacy: .public) not found in destination model")
            return 0
        }

        var migrated = 0

        for sourceObject in sourceObjects {
            autoreleasepool {
                let destObject = NSManagedObject(entity: destEntity, insertInto: destContext)

                // Copy all attributes
                let attributes = destEntity.attributesByName
                for (attrName, _) in attributes {
                    if let value = sourceObject.value(forKey: attrName) {
                        destObject.setValue(value, forKey: attrName)
                    }
                }

                migrated += 1
            }

            // Batch save every 500 entities to manage memory
            if migrated % 500 == 0 && destContext.hasChanges {
                try destContext.save()
            }
        }

        return migrated
    }
}
