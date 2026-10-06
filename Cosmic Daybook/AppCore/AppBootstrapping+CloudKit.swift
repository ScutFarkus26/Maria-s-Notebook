import SwiftUI
import CoreData
import OSLog

// MARK: - Core Data Stack Setup

extension AppBootstrapping {

    /// Creates the Core Data stack with CloudKit sync and comprehensive fallback handling.
    ///
    /// Fallback chain:
    /// 1. CloudKit-enabled two-store stack (private + shared)
    /// 2. Local cached two-store stack using the existing private/shared sqlite files,
    ///    but without CloudKit mirroring
    /// 3. Local-only unified store — only on a device with no private or shared
    ///    store file at all. When they exist and won't open, the launch goes to
    ///    the database-error screen instead: a separate, empty store would look
    ///    like a fresh notebook while the real one sits on disk.
    /// 4. In-memory stack (last resort — data is not persisted)
    ///
    /// Each attempt on disk opens its stores off the main thread
    /// (`openAttempt`), so the window can show "Opening your notebook…"
    /// meanwhile; the choices between attempts stay here.
    static func createCoreDataStack() async throws -> CoreDataStack { // swiftlint:disable:this function_body_length
        let logger = Logger.container
        let useInMemory = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useInMemoryStoreOnce)

        if useInMemory {
            logger.info("Creating in-memory Core Data stack (user requested)")
            let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
            DatabaseInitializationService.markInMemorySession(true)
            UserDefaults.standard.set(
                "Using temporary in-memory store on next launch.",
                forKey: UserDefaultsKeys.lastStoreErrorDescription
            )
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
            return stack
        }

        let enableCloudKit = launchUsesCloudKit()

        logger.info("Creating Core Data stack (CloudKit: \(enableCloudKit))...")
        let containerStart = Date()

        // Attempt 1: CloudKit-enabled stack
        if enableCloudKit {
            do {
                let stack = try await openAttempt(enableCloudKit: true, preserveSplitStoreLayout: false)
                let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
                logger.info("CloudKit Core Data stack created in \(elapsed)s")
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                DatabaseInitializationService.markInMemorySession(false)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return stack
            } catch {
                if isUnrecoverableStoreError(error) { throw error }
                logger.warning("CloudKit stack failed, falling back to local: \(error)")
                // Raw text for diagnostics; the startup banner only checks
                // that it's there and says it in its own words.
                UserDefaults.standard.set(
                    DatabaseErrorCoordinator.technicalDescription(of: error),
                    forKey: UserDefaultsKeys.cloudKitLastErrorDescription
                )
            }
        }

        // Attempt 2: preserve the existing private/shared cache but disable CloudKit.
        // This keeps the app usable with the last successfully downloaded data.
        do {
            let stack = try await openAttempt(enableCloudKit: false, preserveSplitStoreLayout: true)
            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.warning("CloudKit unavailable; using cached local split stores in \(elapsed)s")
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
            DatabaseInitializationService.markInMemorySession(false)
            UserDefaults.standard.set(
                "iCloud sync is temporarily unavailable. Using your last downloaded local data.",
                forKey: UserDefaultsKeys.lastStoreErrorDescription
            )
            return stack
        } catch {
            if isUnrecoverableStoreError(error) { throw error }
            logger.error("Cached split-store fallback failed: \(error)")
            let fm = FileManager.default
            guard mayOpenSeparateLocalStore(
                privateStoreExists: fm.fileExists(atPath: CoreDataStack.privateStoreURL().path),
                sharedStoreExists: fm.fileExists(atPath: CoreDataStack.sharedStoreURL().path)
            ) else {
                throw error
            }
        }

        // Attempt 3: Local-only unified store (no CloudKit)
        do {
            let stack = try await openAttempt(enableCloudKit: false, preserveSplitStoreLayout: false)
            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("Local Core Data stack created in \(elapsed)s")
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
            DatabaseInitializationService.markInMemorySession(false)
            UserDefaults.standard.set(
                "iCloud sync is unavailable, so the app started with a separate local fallback store.",
                forKey: UserDefaultsKeys.lastStoreErrorDescription
            )
            return stack
        } catch {
            if isUnrecoverableStoreError(error) { throw error }
            logger.error("Local stack failed: \(error)")
            DatabaseInitializationService.handleDatabaseInitError(error)
        }

        // Attempt 4: In-memory fallback (allows error UI to render)
        logger.error("Falling back to in-memory stack")
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        let errorDesc = "Persistent storage failed. Using temporary in-memory store."
        DatabaseInitializationService.markInMemorySession(true)
        UserDefaults.standard.set(errorDesc, forKey: UserDefaultsKeys.lastStoreErrorDescription)
        return stack
    }

    /// Whether this launch opens its stores with CloudKit: the guide's
    /// setting (on unless turned off), unless the tests turned it off.
    static func launchUsesCloudKit() -> Bool {
        let preference = UserDefaults.standard.object(forKey: UserDefaultsKeys.enableCloudKitSync) as? Bool ?? true
        return preference && !disableCloudKitForCurrentLaunch
    }

    // MARK: - Opening Early

    /// The chain's first attempt, opening on a background thread since
    /// `CosmicDaybookApp.init` (`startOpeningStores`). The chain itself runs
    /// on the main actor, which a launch keeps busy setting up its first
    /// window for a few hundred milliseconds after `init`; the stores open
    /// meanwhile. Taken, once, by the attempt it is.
    private struct EarlyOpening {
        let enableCloudKit: Bool
        let preserveSplitStoreLayout: Bool
        let task: Task<CoreDataStack.OpenedStores, Error>
    }

    private static var earlyOpening: EarlyOpening?

    /// Starts the chain's first attempt now, on a background thread, then the
    /// shared load that finishes it and decides what follows
    /// (`sharedCoreDataStack()`). `CosmicDaybookApp.init` calls it, so the
    /// stores start opening at launch whether or not a window ever comes.
    /// Nothing opens early under tests (#15) or for the in-memory launch the
    /// guide asked for.
    static func startOpeningStores() {
        defer { sharedStackLoad.start() }
        guard !isRunningUnitTests, earlyOpening == nil, _sharedCoreDataStack == nil,
              !UserDefaults.standard.bool(forKey: UserDefaultsKeys.useInMemoryStoreOnce) else { return }
        // With iCloud sync off the chain starts at the cached split stores.
        let enableCloudKit = launchUsesCloudKit()
        earlyOpening = EarlyOpening(
            enableCloudKit: enableCloudKit,
            preserveSplitStoreLayout: !enableCloudKit,
            task: CoreDataStack.startOpening(enableCloudKit: enableCloudKit, preserveSplitStoreLayout: !enableCloudKit)
        )
    }

    /// One attempt's stack: the early opening when it is this attempt's,
    /// else its stores opened now, off the main thread.
    private static func openAttempt(
        enableCloudKit: Bool,
        preserveSplitStoreLayout: Bool
    ) async throws -> CoreDataStack {
        if let early = earlyOpening {
            earlyOpening = nil
            if early.enableCloudKit == enableCloudKit, early.preserveSplitStoreLayout == preserveSplitStoreLayout {
                return try await CoreDataStack.finish(early.task)
            }
            // Not this attempt's: let it end before opening the same files
            // again (one opening at a time, or two would both do surgery
            // under this copy's one store lock), and let it go.
            Logger.container.notice("The early store opening didn't match the launch's first attempt; dropped")
            // Its stores are closed before the same files open again; with
            // CloudKit on, its mirroring would otherwise keep working on them.
            if let dropped = try? await early.task.value {
                let coordinator = dropped.container.persistentStoreCoordinator
                for store in coordinator.persistentStores { try? coordinator.remove(store) }
            }
        }
        return try await CoreDataStack.load(
            enableCloudKit: enableCloudKit,
            preserveSplitStoreLayout: preserveSplitStoreLayout
        )
    }

    /// True when the user's real store exists but could not be opened — as
    /// opposed to CloudKit merely being unavailable, which the chain below is
    /// designed to ride out.
    ///
    /// These must abandon the fallback chain rather than continue down it.
    /// Every remaining attempt either reuses the same store files — and so
    /// fails the same way — or quietly starts a *different*, empty store. That
    /// presents a first-launch-looking app while the real data sits intact on
    /// disk, and invites the user to type fresh work into the wrong database.
    /// Rethrowing instead lands on the database-error screen, which says what
    /// happened and offers "Re-download from iCloud…".
    static func isUnrecoverableStoreError(_ error: any Error) -> Bool {
        guard let stackError = error as? CoreDataStackError else { return false }
        switch stackError {
        case .storeFromNewerBuild, .storeSchemaIncoherent, .storeInUseByAnotherCopy, .restoreUnfinished:
            return true
        case .storeLoadFailed(let underlying), .cloudKitLoadFailed(let underlying):
            return isFatalStoreError(underlying as NSError)
        case .modelNotFound:
            return false
        }
    }

    /// Migration and version-hash failures mean the bytes on disk are fine but
    /// this build cannot open them. Recoverable — but not by opening something
    /// else and pretending.
    static func isFatalStoreError(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && unopenableStoreErrorCodes.contains(error.code)
    }

    /// Core Data's codes for "this build can't open these bytes"
    /// (`CoreDataErrors.h`): an incompatible schema or version hash, and every
    /// way a migration fails, staged migration's included.
    static let unopenableStoreErrorCodes: Set<Int> = [
        NSPersistentStoreIncompatibleSchemaError,
        NSPersistentStoreIncompatibleVersionHashError,
        NSMigrationError,
        NSMigrationConstraintViolationError,
        NSMigrationCancelledError,
        NSMigrationMissingSourceModelError,
        NSMigrationMissingMappingModelError,
        NSMigrationManagerSourceStoreError,
        NSMigrationManagerDestinationStoreError,
        NSEntityMigrationPolicyError,
        NSInferredMappingModelError,
        NSStagedMigrationFrameworkVersionMismatchError,
        NSStagedMigrationBackwardMigrationError
    ]

    /// Whether the launch may fall back to the separate local store
    /// (`unified.sqlite`): only when the device has neither split store. With
    /// either on disk, that notebook is the guide's, and an empty stand-in
    /// would invite him to type into the wrong database.
    static func mayOpenSeparateLocalStore(privateStoreExists: Bool, sharedStoreExists: Bool) -> Bool {
        !privateStoreExists && !sharedStoreExists
    }
}
