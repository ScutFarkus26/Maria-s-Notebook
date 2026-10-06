// swiftlint:disable file_length
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

    /// The store descriptions for one of the stack's layouts.
    ///
    /// - CloudKit: two stores (private + shared) for the two CloudKit databases.
    /// - Cached split (`preserveSplitStoreLayout`): the same two files without
    ///   CloudKit mirroring, so the last downloaded copy opens when CloudKit
    ///   startup is unhealthy.
    /// - Local: one unified store with every entity, in memory or on disk.
    ///   One store avoids the "Multiple NSEntityDescriptions" problem split
    ///   configurations bring: `+entity` can't disambiguate, and
    ///   `@FetchRequest` crashes.
    nonisolated static func makeStoreDescriptions(
        enableCloudKit: Bool,
        inMemory: Bool,
        preserveSplitStoreLayout: Bool,
        localStoreURL: URL?
    ) -> [NSPersistentStoreDescription] {
        if !inMemory, enableCloudKit || preserveSplitStoreLayout {
            let privateDesc = makeStoreDescription(url: privateStoreURL(), configuration: privateConfiguration)
            let sharedDesc = makeStoreDescription(url: sharedStoreURL(), configuration: sharedConfiguration)
            enableHistoryTracking(privateDesc)
            enableHistoryTracking(sharedDesc)
            if enableCloudKit {
                configureCloudKit(privateDescription: privateDesc, sharedDescription: sharedDesc)
            }
            return [privateDesc, sharedDesc]
        }
        let desc: NSPersistentStoreDescription
        if inMemory {
            desc = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null/unified"))
            desc.type = NSInMemoryStoreType
        } else {
            desc = makeStoreDescription(url: localStoreURL ?? unifiedStoreURL(), configuration: nil)
        }
        enableHistoryTracking(desc)
        return [desc]
    }

    nonisolated static func makeStoreDescription(
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

    nonisolated static func enableHistoryTracking(_ description: NSPersistentStoreDescription) {
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    // MARK: - CloudKit Configuration

    nonisolated static func configureCloudKit(
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

    // MARK: - Store Lock

    /// This environment's store lock (`StoreProcessLock`), beside its stores.
    nonisolated static let storeLock = StoreProcessLock(directory: storeDirectory())

    /// Whether this copy of the app had the store files to itself when it
    /// opened them: the one copy that runs launch repairs and duplicate
    /// cleanup. False for a second copy (the Mac can run several), and for a
    /// process that has only opened in-memory or Sample Class stores.
    nonisolated static var isPrimaryProcess: Bool { storeLock.isPrimary }

    /// Whether another copy of the app had the store files open when this one
    /// opened them. Such a copy never puts records into the classroom share:
    /// the attach lock works within one process only, so two copies could each
    /// share the same record, which stops CloudKit's export (2026-09-27).
    nonisolated static var isSecondaryProcess: Bool { storeLock.isSecondary }

    /// The note the error screen's restore leaves beside the stores when it
    /// couldn't put the notebook back (`FreshNotebookRestore`).
    nonisolated static let unfinishedRestoreMarkerName = ".restore-unfinished"

    /// The folder the notebook is in when such a restore couldn't put it
    /// back, or nil. The launch refuses to open the stores while it's there
    /// (`CoreDataStackError.restoreUnfinished`).
    nonisolated static func unfinishedRestoreFolder(in directory: URL) -> String? {
        let marker = directory.appendingPathComponent(unfinishedRestoreMarkerName)
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Set aside" : name
    }

    /// A second copy becomes the primary once the other copies have quit
    /// (`StoreProcessLock.promoteIfAlone`); true when it is now the primary.
    @discardableResult
    nonisolated static func promoteToPrimaryIfAlone() -> Bool { storeLock.promoteIfAlone() }

    /// How long a launch waits for another copy in the middle of store surgery.
    nonisolated static let storeLockWait: Duration = .seconds(10)

    /// Takes the app's store files at launch: true when this copy has them to
    /// itself, so store surgery may run; false when another copy has them open
    /// (this one then holds them shared and runs none). Throws
    /// `.storeInUseByAnotherCopy` when another copy keeps them for surgery past `wait`.
    nonisolated static func claimStoresForLaunch(
        lock: StoreProcessLock = storeLock,
        wait: Duration = storeLockWait
    ) throws -> Bool {
        if lock.tryExclusive() { return true }
        guard lock.holdShared(timeout: wait) else {
            throw CoreDataStackError.storeInUseByAnotherCopy
        }
        logger.notice("Another copy of the app has the notebook open: opening it without store repairs")
        return false
    }

    // MARK: - Store Reset

    /// Destroys this environment's stores (or `urls`) through Core Data,
    /// which honors SQLite's locks and journal, then removes what's left.
    ///
    /// Deleting the files outright under a connection that still has them
    /// open loses data. Destroying empties the database but leaves an empty
    /// file behind (and makes one for a store that was never there, so
    /// missing ones are skipped); a missing private store is how the next
    /// launch knows it downloads everything (`FirstDownloadGate`), so the
    /// empty files go too. The launch reset holds the store lock, so no other
    /// copy of the app has them open.
    nonisolated static func resetStores(
        _ urls: [URL] = [privateStoreURL(), sharedStoreURL(), unifiedStoreURL()]
    ) throws {
        let fm = FileManager.default
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        for url in urls where fm.fileExists(atPath: url.path) {
            try coordinator.destroyPersistentStore(at: url, type: .sqlite, options: nil)
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

    /// Performs the "Reset Local Cache" sequence:
    ///   1. Destroy the on-disk persistent stores (so the container will
    ///      reconstitute from CloudKit on load).
    ///   2. Clear migration/sharing completion flags so the post-launch
    ///      bootstrap re-runs against the fresh data set.
    ///   3. Clear the request flag so we only do this once per request.
    ///
    /// Only with the store files to this copy of the app: the launch claim
    /// holds them, and any other caller (the Assistant's rebuild) takes them
    /// here. Without them it deletes nothing and returns false. Errors
    /// deleting are logged, not thrown — partial cleanup is still better than
    /// aborting launch with no fallback.
    @discardableResult
    nonisolated static func performLocalCacheReset(defaults: UserDefaults = .standard) -> Bool {
        let lock = storeLock
        let alreadyHeld = lock.holdsExclusive
        guard alreadyHeld || lock.tryExclusive() else {
            logger.error("Reset Local Cache: another copy of the app has the stores open; nothing deleted")
            return false
        }
        defer { if !alreadyHeld { lock.releaseExclusive() } }
        let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
        let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
        let cacheResetMsg = "Reset Local Cache requested — destroying on-disk stores " +
            "and clearing migration flags. source=\(source), armedAt=\(armedAt)"
        logger.warning("\(cacheResetMsg, privacy: .public)")
        do {
            try resetStores()
        } catch {
            // The old stores may still be there: keep what belongs to them (the
            // share's waiting list, the repair ledgers) and forget only the
            // request, so the next launch doesn't retry the reset in a loop.
            logger.error("Reset Local Cache: failed to delete stores — \(error.localizedDescription)")
            clearLocalCacheResetRequest(in: defaults)
            return true
        }
        clearLocalCacheResetFlags(in: defaults)
        return true
    }

    /// The flags that belonged to the deleted stores, and the reset request itself.
    nonisolated static func clearLocalCacheResetFlags(in defaults: UserDefaults) {
        // Records waiting for the classroom share named rows in the deleted
        // store; the download brings back whatever was already shared.
        defaults.removeObject(forKey: UserDefaultsKeys.classroomSharePendingAttach)
        #if !ASSISTANT_APP
        defaults.removeObject(forKey: UserDefaultsKeys.classroomSharePendingAttachStamps)
        #endif
        // The history processor's per-store positions belong to it too.
        defaults.removeObject(forKey: UserDefaultsKeys.persistentHistoryStoreTokens)
        // The fresh store's first check-in repair keeps orphans, as on a new device.
        defaults.removeObject(forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
        defaults.removeObject(forKey: UserDefaultsKeys.orphanStudentGrace)
        // The notebook's own launch-repair flags (the Assistant runs none of them).
        #if !ASSISTANT_APP
        defaults.removeObject(forKey: UserDefaultsKeys.orphanCheckInGrace)
        // A fresh download is checked again for notes saved with no scope.
        defaults.removeObject(forKey: UserDefaultsKeys.noteScopeIndexRepairDone)
        #endif
        clearLocalCacheResetRequest(in: defaults)
    }

    /// Forgets a Re-download request, leaving everything else as it is.
    nonisolated static func clearLocalCacheResetRequest(in defaults: UserDefaults) {
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
    }

    /// Whether the guide wants iCloud sync on this device (the default).
    nonisolated static func syncPreferred(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: UserDefaultsKeys.enableCloudKitSync) as? Bool ?? true
    }

    /// Asks for "Re-download from iCloud" at the next launch: the reset can't
    /// run while the stores are open, so Settings and the database-error
    /// screen arm it, and the next launch carries it out.
    ///
    /// Refused (false) while iCloud sync is off on this device: then nothing
    /// is in iCloud to download, and the reset would delete the only copy.
    @discardableResult
    static func armLocalCacheReset(source: String, defaults: UserDefaults = .standard) -> Bool {
        guard syncPreferred(in: defaults) else {
            logger.notice("Re-download not armed: iCloud sync is off on this device")
            return false
        }
        let armedAt = Date.now.ISO8601Format()
        defaults.set(true, forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.set(armedAt, forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.set(source, forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
        let armedMsg = "Local cache reset armed. source=\(source), armedAt=\(armedAt)"
        logger.warning("\(armedMsg, privacy: .public)")
        return true
    }

    /// What a launch does about an armed Re-download.
    nonisolated enum LocalCacheResetDecision: Equatable {
        case none
        /// Destroy the stores now, before they load.
        case reset
        /// iCloud sync is off: the request is dropped, never carried out,
        /// since this device's copy is the only one.
        case dropSyncOff
        /// Another copy of the app has the stores open: the request stays
        /// armed and this launch doesn't open them (`storeInUseByAnotherCopy`).
        case waitForOtherCopy
    }

    nonisolated static func localCacheResetDecision(
        armed: Bool,
        syncPreferred: Bool,
        surgeryAllowed: Bool
    ) -> LocalCacheResetDecision {
        guard armed else { return .none }
        guard syncPreferred else { return .dropSyncOff }
        return surgeryAllowed ? .reset : .waitForOtherCopy
    }

    /// Runs before the app's on-disk stores load (never for in-memory or
    /// Sample Class stores).
    ///
    /// Honors a deferred "Reset Local Cache" request (Settings, or the
    /// database-error screen): the stores are destroyed BEFORE the container
    /// is created so the next loadPersistentStores reconstitutes from
    /// CloudKit, and migration / sharing completion flags are cleared so
    /// post-launch bootstrap re-runs against the fresh data. Without the store
    /// files to itself (`surgeryAllowed`), the launch stops here instead and
    /// the request stays armed for the next one.
    ///
    /// Then a missing private store file means this launch downloads
    /// everything from iCloud (a reset, or a new device), so zone repair and
    /// template seeding wait for that first import (`FirstDownloadGate`).
    nonisolated static func prepareOnDiskStores(
        enableCloudKit: Bool,
        surgeryAllowed: Bool = true,
        defaults: UserDefaults = .standard
    ) throws {
        let decision = localCacheResetDecision(
            armed: defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch),
            syncPreferred: syncPreferred(in: defaults),
            surgeryAllowed: surgeryAllowed
        )
        let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
        let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
        switch decision {
        case .none:
            break
        case .reset:
            let resetMsg = "Consuming pending local cache reset before store load. " +
                "source=\(source), armedAt=\(armedAt)"
            logger.warning("\(resetMsg, privacy: .public)")
            performLocalCacheReset(defaults: defaults)
        case .dropSyncOff:
            logger.error("Pending local cache reset dropped: iCloud sync is off, so it would delete the only copy")
            clearLocalCacheResetRequest(in: defaults)
        case .waitForOtherCopy:
            logger.error("Pending local cache reset waits: another copy of the app has the stores open")
            throw CoreDataStackError.storeInUseByAnotherCopy
        }

        updateFirstDownloadGate(
            enableCloudKit: enableCloudKit,
            privateStoreExists: FileManager.default.fileExists(atPath: privateStoreURL().path),
            defaults: defaults
        )
    }

    /// Arms the gate for a CloudKit launch with no private store yet, and
    /// opens it only when the guide has turned iCloud sync off, so no import
    /// will ever come. A launch that fell back to local stores because
    /// CloudKit failed leaves it as it was: the download resumes when CloudKit
    /// does, and the half-downloaded store must not be judged whole meanwhile
    /// (once open, nothing re-arms it — the store file exists by then).
    nonisolated static func updateFirstDownloadGate(
        enableCloudKit: Bool,
        privateStoreExists: Bool,
        defaults: UserDefaults
    ) {
        let syncPreferred = defaults.object(forKey: UserDefaultsKeys.enableCloudKitSync) as? Bool ?? true
        if enableCloudKit {
            if !privateStoreExists {
                FirstDownloadGate.arm(defaults: defaults)
            }
        } else if !syncPreferred {
            FirstDownloadGate.open(defaults: defaults)
        }
    }
}
