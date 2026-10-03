import Foundation
import CoreData
import OSLog

// MARK: - Database Initialization Service

/// Service for initializing and managing the Core Data database container.
enum DatabaseInitializationService {

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
        markInMemorySession(false)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)

        AppBootstrapping.initError = nil
        DatabaseErrorCoordinator.shared.clearError()
    }
    #endif

    // MARK: - Session flags

    /// Records whether this session runs on an in-memory store, where nothing
    /// saves. Called wherever the launch picks (or leaves) the in-memory
    /// fallback; the safe-mode banner reads `inMemoryStoreSession` rather than
    /// searching the stored reason's wording.
    static func markInMemorySession(_ inMemory: Bool) {
        UserDefaults.standard.set(inMemory, forKey: UserDefaultsKeys.ephemeralSessionFlag)
        UserDefaults.standard.set(inMemory, forKey: UserDefaultsKeys.inMemoryStoreSession)
    }

    // MARK: - Error Handling

    /// Centralized error handling for database initialization failures. The
    /// error screen words the error plainly (`DatabaseErrorCoordinator.userMessage`);
    /// its raw text is kept for the screen's Details and diagnostics.
    static func handleDatabaseInitError(_ error: Error) {
        let details = DatabaseErrorCoordinator.technicalDescription(of: error)
        AppBootstrapping.initError = error
        DatabaseErrorCoordinator.shared.setError(error, details: details)
        markInMemorySession(true)
        UserDefaults.standard.set(details, forKey: UserDefaultsKeys.lastStoreErrorDescription)
    }

}
