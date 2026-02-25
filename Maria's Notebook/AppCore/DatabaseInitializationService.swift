import Foundation
import SwiftData
import CoreData
import OSLog

// MARK: - Database Initialization Service

/// Service for initializing and managing the SwiftData database container.
enum DatabaseInitializationService {

    // MARK: - Logger

    private static let logger = Logger.database

    private static let resetLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook",
        category: "Reset"
    )

    // MARK: - Store URL

    /// Returns the URL for the SwiftData store file.
    static func storeFileURL() -> URL {
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
            return fm.temporaryDirectory.appendingPathComponent("SwiftData.store", isDirectory: false)
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "MariasNotebook"
        let containerDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: containerDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create container directory: \(error)")
        }
        return containerDir.appendingPathComponent("SwiftData.store", isDirectory: false)
    }

    // MARK: - Reset Operations

    /// Deletes the SwiftData persistent store file/package.
    /// This only deletes local data on this device and does NOT delete CloudKit data.
    static func resetPersistentStore() throws {
        let url = storeFileURL()
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return
        }

        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    #if DEBUG
    /// Resets the local database by deleting SwiftData store files and clearing related state.
    /// This is a DEBUG-only function that performs a complete reset.
    @MainActor
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

    // MARK: - Migration

    /// Attempts to migrate AttendanceRecord.studentID from UUID to String.
    /// Returns true if migration was successful or not needed.
    static func attemptAttendanceRecordMigrationIfNeeded() -> Bool {
        let storeURL = storeFileURL()
        let fm = FileManager.default

        guard fm.fileExists(atPath: storeURL.path) else {
            return true
        }

        let migrationFlagKey = "Migration.attendanceRecordStudentIDCoreData.v1"
        if UserDefaults.standard.bool(forKey: migrationFlagKey) {
            return true
        }

        return true
    }

    // MARK: - SQLite Configuration

    /// Configures SQLite to suppress detached signature logging errors.
    /// Note: WAL checkpoint optimization is handled by disabling autosave and batching saves in SaveCoordinator.
    static func configureSQLiteToSuppressDetachedSignatureErrors(for container: ModelContainer) {
        _ = container
        // WAL checkpoint contention is primarily managed by:
        // 1. Disabling autosave on main context (see AppBootstrapping)
        // 2. Batching saves through SaveCoordinator
        // 3. Removing unnecessary immediate saves throughout the codebase
    }

    // MARK: - Error Handling

    /// Centralized error handling for database initialization failures.
    @MainActor
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

    /// Handles critical database initialization failure with multiple error contexts.
    @MainActor
    static func handleCriticalDatabaseInitError(
        originalError: Error,
        finalError: Error? = nil,
        emptyContainerError: Error? = nil,
        errorCode: Int = 5002
    ) {
        let originalDesc = (originalError as NSError?)?.localizedDescription ?? String(describing: originalError)
        let finalDesc = (finalError as NSError?)?.localizedDescription ?? "N/A"
        let emptyErrorDesc = (emptyContainerError as NSError?)?.localizedDescription ?? "N/A"

        let errorMessage: String
        if emptyContainerError != nil {
            errorMessage = "Critical database initialization failure. Failed to create even an empty container. This indicates a severe system issue. Original: \(originalDesc). Final: \(finalDesc). Empty container error: \(emptyErrorDesc). Please try resetting the database or reinstalling the app."
        } else if finalError != nil {
            errorMessage = "Critical database initialization failure. The app cannot create a database container. Original: \(originalDesc). Final: \(finalDesc). Please try resetting the database or reinstalling the app."
        } else {
            errorMessage = "Critical database initialization failure. Original: \(originalDesc). Please try resetting the database or reinstalling the app."
        }

        let criticalError = NSError(
            domain: "MariasNotebook",
            code: errorCode,
            userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )

        AppBootstrapping.initError = criticalError
        let details = emptyContainerError != nil
            ? "Original: \(originalDesc). Final: \(finalDesc). Empty container error: \(emptyErrorDesc)"
            : "Original: \(originalDesc). Final: \(finalDesc)"
        DatabaseErrorCoordinator.shared.setError(criticalError, details: details)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
        UserDefaults.standard.set(criticalError.localizedDescription, forKey: UserDefaultsKeys.lastStoreErrorDescription)
    }
}
