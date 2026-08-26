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
    /// 3. Local-only unified store
    /// 4. In-memory stack (last resort — data is not persisted)
    // swiftlint:disable:next function_body_length
    static func createCoreDataStack() throws -> CoreDataStack {
        let logger = Logger.app(category: "Container")
        let useInMemory = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useInMemoryStoreOnce)

        if useInMemory {
            logger.info("Creating in-memory Core Data stack (user requested)")
            let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
            UserDefaults.standard.set(
                "Using temporary in-memory store on next launch.",
                forKey: UserDefaultsKeys.lastStoreErrorDescription
            )
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
            return stack
        }

        // CloudKit preference (defaults to enabled)
        let cloudKitPreference = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.enableCloudKitSync
        ) as? Bool ?? true
        let enableCloudKit = cloudKitPreference && !AppBootstrapping.disableCloudKitForCurrentLaunch

        logger.info("Creating Core Data stack (CloudKit: \(enableCloudKit))...")
        let containerStart = Date()

        // Attempt 1: CloudKit-enabled stack
        if enableCloudKit {
            do {
                let stack = try CoreDataStack(enableCloudKit: true, inMemory: false)
                let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
                logger.info("CloudKit Core Data stack created in \(elapsed)s")
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return stack
            } catch {
                if isStoreFromNewerBuild(error) { throw error }
                logger.warning("CloudKit stack failed, falling back to local: \(error)")
                let detailedError = (error as NSError).localizedDescription
                UserDefaults.standard.set(
                    detailedError,
                    forKey: UserDefaultsKeys.cloudKitLastErrorDescription
                )
            }
        }

        // Attempt 2: preserve the existing private/shared cache but disable CloudKit.
        // This keeps the app usable with the last successfully downloaded data.
        do {
            let stack = try CoreDataStack(
                enableCloudKit: false,
                inMemory: false,
                preserveSplitStoreLayout: true
            )
            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.warning("CloudKit unavailable; using cached local split stores in \(elapsed)s")
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
            UserDefaults.standard.set(
                "iCloud sync is temporarily unavailable. Using your last downloaded local data.",
                forKey: UserDefaultsKeys.lastStoreErrorDescription
            )
            return stack
        } catch {
            if isStoreFromNewerBuild(error) { throw error }
            logger.error("Cached split-store fallback failed: \(error)")
        }

        // Attempt 3: Local-only unified store (no CloudKit)
        do {
            let stack = try CoreDataStack(enableCloudKit: false, inMemory: false)
            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("Local Core Data stack created in \(elapsed)s")
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
            UserDefaults.standard.set(
                "iCloud sync is unavailable, so the app started with a separate local fallback store.",
                forKey: UserDefaultsKeys.lastStoreErrorDescription
            )
            return stack
        } catch {
            if isStoreFromNewerBuild(error) { throw error }
            logger.error("Local stack failed: \(error)")
            DatabaseInitializationService.handleDatabaseInitError(error)
        }

        // Attempt 4: In-memory fallback (allows error UI to render)
        logger.error("Falling back to in-memory stack")
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        let errorDesc = "Persistent storage failed. Using temporary in-memory store."
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
        UserDefaults.standard.set(errorDesc, forKey: UserDefaultsKeys.lastStoreErrorDescription)
        return stack
    }

    /// True when the stack refused to open a store because a newer build wrote
    /// it (`CoreDataStack.verifyStoreIsNotFromNewerBuild`).
    ///
    /// This must abandon the fallback chain rather than continue down it. Every
    /// remaining attempt either reuses the same store files — and so fails the
    /// same way — or quietly starts a *different*, empty store, which presents
    /// a first-launch-looking app while the real data sits intact on disk. The
    /// caller turns the rethrow into the database-error screen, which says what
    /// actually happened and what to do about it.
    private static func isStoreFromNewerBuild(_ error: any Error) -> Bool {
        guard let stackError = error as? CoreDataStackError else { return false }
        if case .storeFromNewerBuild = stackError { return true }
        return false
    }
}
