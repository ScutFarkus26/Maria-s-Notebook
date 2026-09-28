import CloudKit
import CoreData
import OSLog

extension CoreDataStack {
    // MARK: - Store URLs

    /// The app's folder for Core Data store files. Development's CloudKit
    /// stores and Sample Class live directly in it.
    nonisolated static func baseStoreDirectory() -> URL {
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
        return makeDirectory(appSupport.appendingPathComponent(bundleID, isDirectory: true))
    }

    /// Directory for this build's CloudKit notebook: the base folder for
    /// Development, `Production/` inside it for Production. Each environment is
    /// a separate notebook, so neither ever opens the other's files — going
    /// back to a Development build finds its store exactly as it was left.
    nonisolated static func storeDirectory(
        environment: CloudKitEnvironment = .current
    ) -> URL {
        let base = baseStoreDirectory()
        guard let subfolder = environment.storeSubdirectory else { return base }
        return makeDirectory(base.appendingPathComponent(subfolder, isDirectory: true))
    }

    private nonisolated static func makeDirectory(_ dir: URL) -> URL {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
    /// a filter over the guide's real records. It never syncs, so it belongs to
    /// neither CloudKit environment and stays in the base folder.
    nonisolated static func sampleClassroomStoreURL() -> URL {
        baseStoreDirectory().appendingPathComponent("sample-classroom.sqlite")
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

    /// Deletes this environment's Core Data store files and their WAL/SHM
    /// companions.
    nonisolated static func resetStores() throws {
        let fm = FileManager.default
        for url in [privateStoreURL(), sharedStoreURL(), unifiedStoreURL()] {
            for file in storeFiles(for: url) where fm.fileExists(atPath: file.path) {
                try fm.removeItem(at: file)
            }
        }
        logger.info("Core Data stores reset")
    }

    /// A SQLite store's file and its companions. SQLite names them by
    /// appending `-wal` and `-shm` to the whole file name (`private.sqlite-wal`);
    /// until 2026-09-28 the reset looked for `private.sqlite.wal`, never found
    /// it, and left the old WAL beside the fresh store.
    nonisolated static func storeFiles(for storeURL: URL) -> [URL] {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        return [storeURL] + ["-wal", "-shm"].map { directory.appendingPathComponent(name + $0) }
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
        // Records waiting for the classroom share named rows in the deleted
        // store; the download brings back whatever was already shared.
        defaults.removeObject(forKey: UserDefaultsKeys.classroomSharePendingAttach)
        // The history processor's per-store positions belong to it too.
        defaults.removeObject(forKey: UserDefaultsKeys.persistentHistoryStoreTokens)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
    }

    /// Runs before the app's on-disk stores load (never for in-memory or
    /// Sample Class stores).
    ///
    /// Honors a deferred "Reset Local Cache" request from Settings → Database:
    /// the stores are deleted BEFORE the container is created so the next
    /// loadPersistentStores reconstitutes from CloudKit, and migration /
    /// sharing completion flags are cleared so post-launch bootstrap re-runs
    /// against the fresh data.
    ///
    /// Then a missing private store file means this launch downloads
    /// everything from iCloud (a reset, or a new device), so zone repair and
    /// template seeding wait for that first import (`FirstDownloadGate`). With
    /// CloudKit off no import will come, so nothing waits.
    static func prepareOnDiskStores(enableCloudKit: Bool) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch) {
            let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
            let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
            let resetMsg = "Consuming pending local cache reset before store load. " +
                "source=\(source), armedAt=\(armedAt)"
            logger.warning("\(resetMsg, privacy: .public)")
            performLocalCacheReset()
        }

        if !enableCloudKit {
            FirstDownloadGate.open()
        } else if !FileManager.default.fileExists(atPath: privateStoreURL().path) {
            FirstDownloadGate.arm()
        }
    }
}
