import CloudKit
import CoreData
import OSLog

extension CoreDataStack {
    // MARK: - Store URLs

    /// Directory for Core Data store files.
    nonisolated static func storeDirectory() -> URL {
        let fm = FileManager.default
        let appSupport: URL
        do {
            appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            logger.warning("Failed to get application support directory: \(error)")
            return fm.temporaryDirectory
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "CosmicDaybook"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create store directory: \(error)")
        }
        return dir
    }

    nonisolated static func privateStoreURL() -> URL {
        storeDirectory().appendingPathComponent("private.sqlite")
    }

    nonisolated static func sharedStoreURL() -> URL {
        storeDirectory().appendingPathComponent("shared.sqlite")
    }

    /// Unified store URL for local-only mode (single store, all entities).
    nonisolated static func unifiedStoreURL() -> URL {
        storeDirectory().appendingPathComponent("unified.sqlite")
    }

    /// Local-only store used by Sample Class. Keeping it in a separate SQLite
    /// file makes the sample classroom a hard persistence boundary rather than
    /// a filter over the guide's real records.
    nonisolated static func sampleClassroomStoreURL() -> URL {
        storeDirectory().appendingPathComponent("sample-classroom.sqlite")
    }
    // MARK: - Store Accessors

    /// The NSPersistentStore for the shared (classroom-level) configuration.
    var sharedPersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == Self.sharedConfiguration
        }
    }

    /// The NSPersistentStore for the private (per-teacher) configuration.
    var privatePersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == Self.privateConfiguration
        }
    }

    // MARK: - Store Description Builders

    static func makeStoreDescription(
        url: URL,
        configuration: String?
    ) -> NSPersistentStoreDescription {
        let desc = NSPersistentStoreDescription(url: url)
        if let configuration {
            desc.configuration = configuration
        }
        desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        return desc
    }

    static func enableHistoryTracking(_ description: NSPersistentStoreDescription) {
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    // MARK: - CloudKit Configuration

    static func configureCloudKit(
        privateDescription: NSPersistentStoreDescription,
        sharedDescription: NSPersistentStoreDescription
    ) {
        guard let containerID = CloudKitConfigurationService.getContainerID() else {
            logger.warning("No CloudKit container ID found, skipping CloudKit configuration")
            return
        }

        // Private store → private CloudKit database
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        // Shared store → shared CloudKit database
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        logger.info("CloudKit configured: container=\(containerID)")
    }

    // MARK: - Store Reset

    /// Deletes both Core Data store files and their WAL/SHM companions.
    nonisolated static func resetStores() throws {
        let fm = FileManager.default
        for url in [privateStoreURL(), sharedStoreURL(), unifiedStoreURL()] {
            guard fm.fileExists(atPath: url.path) else { continue }
            try fm.removeItem(at: url)
            // Also remove WAL and SHM files
            let walURL = url.appendingPathExtension("wal")
            let shmURL = url.appendingPathExtension("shm")
            if fm.fileExists(atPath: walURL.path) { try fm.removeItem(at: walURL) }
            if fm.fileExists(atPath: shmURL.path) { try fm.removeItem(at: shmURL) }
        }
        logger.info("Core Data stores reset")
    }

    /// Performs the "Reset Local Cache" sequence at launch:
    ///   1. Delete the on-disk persistent stores (so the container will
    ///      reconstitute from CloudKit on load).
    ///   2. Clear migration/sharing completion flags so the post-launch
    ///      bootstrap re-runs against the fresh data set.
    ///   3. Clear the request flag so we only do this once per request.
    ///
    /// Caller must verify `resetLocalCacheOnLaunch` is true before invoking.
    /// Any errors are logged but not thrown — partial cleanup is still better
    /// than aborting launch with no fallback.
    static func performLocalCacheReset() {
        let defaults = UserDefaults.standard
        let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
        let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
        let cacheResetMsg = "Reset Local Cache requested — deleting on-disk stores " +
            "and clearing migration flags. source=\(source), armedAt=\(armedAt)"
        logger.warning("\(cacheResetMsg, privacy: .public)")
        do {
            try resetStores()
        } catch {
            logger.error("Reset Local Cache: failed to delete stores — \(error.localizedDescription)")
        }
        // Re-run one-shot migrations / share auto-create against the fresh
        // data so the post-refactor state is consistent.
        defaults.removeObject(forKey: UserDefaultsKeys.classroomStoreMigrationV1Complete)
        defaults.removeObject(forKey: UserDefaultsKeys.sharedStoreZoneRepairLastTimeoutAt)
        // The clean watermark belongs to the store file being deleted.
        defaults.removeObject(forKey: UserDefaultsKeys.sharedStoreZoneRepairCleanHistoryToken)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
    }
}
