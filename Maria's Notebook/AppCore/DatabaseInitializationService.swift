import Foundation
import CoreData
import OSLog

// MARK: - Database Initialization Service

/// Service for initializing and managing the Core Data database container.
enum DatabaseInitializationService {

    // MARK: - Logger

    private static let logger = Logger.database

    private static let resetLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook",
        category: "Reset"
    )

    // MARK: - Store URL

    /// Returns the URL of the primary on-disk store (the private store).
    ///
    /// This is used only by the error-diagnostics export so it can report a
    /// real, existing store file. The actual reset path uses
    /// `CoreDataStack.resetStores()`, which removes every store. This used to
    /// return a single `SwiftData.store` path — a leftover from the
    /// pre-Core-Data migration that never exists on disk.
    static func storeFileURL() -> URL {
        CoreDataStack.privateStoreURL()
    }

    // MARK: - Reset Operations

    /// Deletes the on-disk persistent stores.
    /// This only deletes local data on this device and does NOT delete CloudKit data.
    static func resetPersistentStore() throws {
        // Delegate to the canonical reset, which removes the real
        // private/shared/unified SQLite stores plus their WAL/SHM companions.
        // This previously deleted a single "SwiftData.store" file — a leftover
        // from the pre-Core-Data migration that never exists on disk — so the
        // user-facing "Reset Local Database" recovery silently did nothing,
        // leaving users stuck on the database-error screen.
        try CoreDataStack.resetStores()
    }

    #if DEBUG
    /// Resets the local database by deleting store files and clearing related state.
    /// This is a DEBUG-only function that performs a complete reset.
    static func resetLocalDatabaseInDebug() throws {
        try resetPersistentStore()

        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)

        AppBootstrapping.initError = nil
        DatabaseErrorCoordinator.shared.clearError()
    }
    #endif

    /// Resets the local store and enables CloudKit sync.
    static func resetLocalDatabaseAndForceCloudKitSync() throws {
        try resetPersistentStore()

        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
    }

    // MARK: - Error Handling

    /// Centralized error handling for database initialization failures.
    static func handleDatabaseInitError(_ error: Error, description: String? = nil) {
        let errorDescription = description ?? ((error as NSError?)?.localizedDescription ?? String(describing: error))
        let nsError = error as NSError? ?? NSError(
            domain: "MariasNotebook",
            code: 5000,
            userInfo: [NSLocalizedDescriptionKey: errorDescription]
        )

        AppBootstrapping.initError = nsError
        DatabaseErrorCoordinator.shared.setError(nsError)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
        UserDefaults.standard.set(errorDescription, forKey: UserDefaultsKeys.lastStoreErrorDescription)
    }

}
