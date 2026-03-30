import SwiftUI
import CoreData
import OSLog

// MARK: - Core Data Stack Setup

extension AppBootstrapping {

    /// Creates the Core Data stack with CloudKit sync and comprehensive fallback handling.
    ///
    /// Fallback chain:
    /// 1. CloudKit-enabled two-store stack (private + shared)
    /// 2. Local-only two-store stack (no CloudKit sync)
    /// 3. In-memory stack (last resort — data is not persisted)
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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

        // CloudKit preference
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
                logger.warning("CloudKit stack failed, falling back to local: \(error)")
                let detailedError = (error as NSError).localizedDescription
                UserDefaults.standard.set(
                    detailedError,
                    forKey: UserDefaultsKeys.cloudKitLastErrorDescription
                )
            }
        }

        // Attempt 2: Local-only stack (no CloudKit)
        do {
            let stack = try CoreDataStack(enableCloudKit: false, inMemory: false)
            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("Local Core Data stack created in \(elapsed)s")
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
            return stack
        } catch {
            logger.error("Local stack failed: \(error)")
            DatabaseInitializationService.handleDatabaseInitError(error)
        }

        // Attempt 3: In-memory fallback (allows error UI to render)
        logger.error("Falling back to in-memory stack")
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        let errorDesc = "Persistent storage failed. Using temporary in-memory store."
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
        UserDefaults.standard.set(errorDesc, forKey: UserDefaultsKeys.lastStoreErrorDescription)
        return stack
    }
}
