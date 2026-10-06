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
    /// real, existing store file. The reset itself is
    /// `CoreDataStack.performLocalCacheReset()`, armed for the next launch.
    /// This used to return a single `SwiftData.store` path — a leftover from
    /// the pre-Core-Data migration that never exists on disk.
    static func storeFileURL() -> URL {
        CoreDataStack.privateStoreURL()
    }

    // MARK: - Reset Operations

    #if DEBUG
    /// Arms the reset for the next launch (`CoreDataStack.armLocalCacheReset`),
    /// which destroys the stores under the store lock before anything opens
    /// them; the caller quits. It used to delete the files here, with the
    /// stores open in this process and perhaps in another copy of the app (a
    /// Debug build opens the real notebook). False, and nothing armed, while
    /// iCloud sync is off: this device's copy would be the only one.
    static func armLocalDatabaseResetInDebug() -> Bool {
        guard CoreDataStack.armLocalCacheReset(source: "Debug.ResetLocalDatabase") else { return false }
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
        markInMemorySession(false)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
        return true
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
