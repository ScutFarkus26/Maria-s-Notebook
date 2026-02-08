//
//  AppBootstrapping.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import SwiftData
import CoreData
import OSLog

/// Handles all app initialization, database setup, and lifecycle management.
final class AppBootstrapping {
    
    // MARK: - Shared Instance
    
    /// Track initialization errors to show in the UI
    @MainActor
    static var initError: Error?
    
    /// Model container for SwiftData.
    /// Initialized on first access via the static factory method.
    /// If SwiftData asserts internally during schema processing, we cannot catch it.
    @MainActor
    private static var _sharedModelContainer: ModelContainer?
    
    // MARK: - Logger
    
    private static let resetLogger = Logger.app(category: "Reset")
    
    // MARK: - Store Management
    
    /// Deletes the SwiftData persistent store file/package.
    /// This only deletes local data on this device and does NOT delete CloudKit data.
    static func resetPersistentStore() throws {
        try DatabaseInitializationService.resetPersistentStore()
    }

    #if DEBUG
    /// Resets the local database by deleting SwiftData store files and clearing related state.
    /// This is a DEBUG-only function that performs a complete reset.
    static func resetLocalDatabaseInDebug() throws {
        try DatabaseInitializationService.resetLocalDatabaseInDebug()
    }
    
    #if os(macOS)
    /// Shows a confirmation dialog and resets the local database if confirmed.
    /// This is a DEBUG-only function that requires user confirmation before resetting.
    static func requestResetLocalDatabaseWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Reset Local Database?"
        alert.informativeText = "This deletes local data on this device. CloudKit data is preserved and will re-sync after restart. The app will restart automatically."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // User confirmed - perform reset
            do {
                try resetLocalDatabaseInDebug()
                // Terminate app to restart cleanly
                NSApplication.shared.terminate(nil)
            } catch {
                // Show error alert
                let errorAlert = NSAlert(error: error)
                errorAlert.messageText = "Reset Failed"
                errorAlert.informativeText = "Failed to reset local database: \(error.localizedDescription)"
                errorAlert.runModal()
            }
        }
    }
    #endif
    #endif
    
    static func resetLocalDatabaseAndForceCloudKitSync() throws {
        try DatabaseInitializationService.resetLocalDatabaseAndForceCloudKitSync()
    }

    static func storeFileURL() -> URL {
        DatabaseInitializationService.storeFileURL()
    }

    /// Attempts to migrate AttendanceRecord.studentID from UUID to String.
    /// Returns true if migration was successful or not needed.
    static func attemptAttendanceRecordMigrationIfNeeded() -> Bool {
        DatabaseInitializationService.attemptAttendanceRecordMigrationIfNeeded()
    }

    /// Configures SQLite to suppress detached signature logging errors.
    static func configureSQLiteToSuppressDetachedSignatureErrors(for container: ModelContainer) {
        DatabaseInitializationService.configureSQLiteToSuppressDetachedSignatureErrors(for: container)
    }
    
    // MARK: - Container Creation
    
    /// Creates a ModelContainer with comprehensive error handling.
    /// If SwiftData asserts internally during schema processing, we cannot catch it.
    /// Returns the container and sets initError if there's a recoverable error.
    static func createModelContainer() throws -> ModelContainer {
        // IMPORTANT: If SwiftData asserts internally during schema processing, we cannot catch it.
        // Internal assertions crash immediately at the Swift runtime level.
        // 
        // Common causes of SwiftData internal assertions:
        // 1. Duplicate entity names in the schema
        // 2. Invalid or circular relationship definitions
        // 3. Model classes with invalid @Attribute or @Relationship annotations
        // 4. Missing inverse relationships when one side specifies inverse:
        // 5. Invalid property types (e.g., using types SwiftData doesn't support)
        
        // Get schema - if SwiftData asserts here, it's a schema definition problem
        let schema = AppSchema.schema
        
        let useInMemory = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useInMemoryStoreOnce)
        
        // Helper to extract detailed error message from NSError
        func extractDetailedErrorMessage(_ error: Error) -> String {
            let errorDescription = (error as NSError?)?.localizedDescription ?? String(describing: error)
            guard let nsError = error as NSError? else {
                return errorDescription
            }
            
            let userInfo = nsError.userInfo
            if let underlyingError = userInfo[NSUnderlyingErrorKey] as? NSError {
                return underlyingError.localizedDescription
            } else if let errorMessage = userInfo[NSLocalizedDescriptionKey] as? String {
                return errorMessage
            }
            return errorDescription
        }
        
        // Helper to create CloudKit-enabled container with fallback handling
        func createCloudKitContainer(schema: Schema, storeURL: URL, containerID: String) throws -> ModelContainer {
            guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) else {
                throw NSError(domain: "MariasNotebook", code: 2002, userInfo: [NSLocalizedDescriptionKey: "CloudKit requires iOS 17 / macOS 14 or later for SwiftData."])
            }
            
            do {
                let cloudKitLogger = Logger.app(category: "CloudKit")
                let cloudKitStart = Date()
                cloudKitLogger.info("Starting CloudKit container initialization...")
                
                let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .private(containerID))
                let container = try ModelContainer(for: schema, configurations: config)
                
                cloudKitLogger.info("CloudKit container created in \(String(format: "%.3f", Date().timeIntervalSince(cloudKitStart)))s")
                
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
                // Clear any previous error since CloudKit is now active
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                return container
            } catch {
                // CloudKit initialization failed - fall back to local store
                // Store the error for display in the UI
                let detailedError = extractDetailedErrorMessage(error)
                UserDefaults.standard.set(detailedError, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                // Fall back to local store
                let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: config)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                return container
            }
        }
        
        // Helper to create container with defensive error handling
        func makeContainer(inMemory: Bool, url: URL? = nil, cloud: Bool = false) throws -> ModelContainer {
            do {
                if inMemory {
                    let config = ModelConfiguration(isStoredInMemoryOnly: true)
                    // SwiftData may assert here if the schema is invalid
                    let container = try ModelContainer(for: schema, configurations: config)
                    return container
                } else if cloud {
                    // Use the container ID from entitlements (must match entitlements file)
                    let storeURL = url ?? AppBootstrapping.storeFileURL()
                    
                    // Validate store URL is not /dev/null or invalid
                    guard storeURL.path != "/dev/null" && !storeURL.path.isEmpty else {
                        throw NSError(
                            domain: "MariasNotebook",
                            code: 2003,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid store URL: \(storeURL.path). Cannot initialize CloudKit with invalid store location."]
                        )
                    }
                    
                    // Check if iCloud is available before attempting CloudKit container creation
                    if FileManager.default.ubiquityIdentityToken == nil {
                        // Store error state
                        let errorMessage = "Not signed into iCloud. Please sign in to System Settings > Apple ID > iCloud to enable sync."
                        UserDefaults.standard.set(errorMessage, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                        // Fall back to local store
                        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                        let container = try ModelContainer(for: schema, configurations: config)
                        return container
                    }
                    
                    guard let containerID = CloudKitConfiguration.getCloudKitContainerID() else {
                        let errorMessage = "Missing CloudKit container identifier. CloudKit sync cannot be initialized."
                        UserDefaults.standard.set(errorMessage, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                        let container = try ModelContainer(for: schema, configurations: config)
                        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                        return container
                    }

                    return try createCloudKitContainer(schema: schema, storeURL: storeURL, containerID: containerID)
                } else {
                    // Explicitly disable CloudKit for SwiftData (we use CloudDocuments for file storage instead)
                    let config = ModelConfiguration(
                        url: url ?? AppBootstrapping.storeFileURL(),
                        cloudKitDatabase: .none
                    )
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                    return try ModelContainer(for: schema, configurations: config)
                }
            } catch {
                // Re-throw with additional context
                throw error
            }
        }

        do {
            let logger = Logger.app(category: "Container")
            
            // Attempt migration before opening store (if needed)
            let migrationCheckStart = Date()
            _ = AppBootstrapping.attemptAttendanceRecordMigrationIfNeeded()
            logger.info("createModelContainer: Migration check completed in \(String(format: "%.3f", Date().timeIntervalSince(migrationCheckStart)))s")
            
            let ubiquityStart = Date()
            let _ = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            logger.info("createModelContainer: Ubiquity check completed in \(String(format: "%.3f", Date().timeIntervalSince(ubiquityStart)))s")
            
            if useInMemory {
                let container = try makeContainer(inMemory: true)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set("Using temporary in-memory store on next launch.", forKey: UserDefaultsKeys.lastStoreErrorDescription)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
                return container
            } else {
                // Validate store file before attempting to open
                let validationStart = Date()
                let storeURL = AppBootstrapping.storeFileURL()
                let fm = FileManager.default
                if fm.fileExists(atPath: storeURL.path) {
                    // Check if the store file is readable
                    guard fm.isReadableFile(atPath: storeURL.path) else {
                        throw NSError(
                            domain: "MariasNotebook",
                            code: 6001,
                            userInfo: [NSLocalizedDescriptionKey: "Store file exists but is not readable. The database may be corrupted or locked by another process."]
                        )
                    }
                }
                logger.info("createModelContainer: Store validation completed in \(String(format: "%.3f", Date().timeIntervalSince(validationStart)))s")
                
                // CloudKit compatibility: All model fixes are complete. Enable CloudKit by default.
                // Users can disable it via the settings toggle if needed.
                let enableCloudKit = UserDefaults.standard.object(forKey: UserDefaultsKeys.enableCloudKitSync) as? Bool ?? true
                
                let containerCreateStart = Date()
                logger.info("createModelContainer: Starting container creation (CloudKit: \(enableCloudKit))...")
                
                // Try CloudKit first if enabled, but fall back to local if it takes too long or fails
                let container: ModelContainer
                if enableCloudKit {
                    do {
                        container = try makeContainer(inMemory: false, cloud: true)
                        logger.info("createModelContainer: CloudKit container created in \(String(format: "%.3f", Date().timeIntervalSince(containerCreateStart)))s")
                    } catch {
                        logger.warning("createModelContainer: CloudKit initialization failed, falling back to local storage: \(error.localizedDescription)")
                        // Fall back to local storage if CloudKit fails
                        container = try makeContainer(inMemory: false, cloud: false)
                        logger.info("createModelContainer: Local container created as fallback in \(String(format: "%.3f", Date().timeIntervalSince(containerCreateStart)))s")
                    }
                } else {
                    container = try makeContainer(inMemory: false, cloud: false)
                    logger.info("createModelContainer: Local container created in \(String(format: "%.3f", Date().timeIntervalSince(containerCreateStart)))s")
                }
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                if !enableCloudKit {
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                }
                return container
            }
        } catch {
            // If even the in-memory fallback fails, we must surface the blocking error view instead of crashing.
            if let nsError = error as NSError? {
                
                // Check if this is a migration error (code 134140 or 134190)
                if nsError.code == 134140 || nsError.code == 134190 {
                    // This is a schema migration error
                    // Check if it's specifically about AttendanceRecord.studentID
                    let userInfo = nsError.userInfo
                    if let entity = userInfo["entity"] as? String,
                       entity == "AttendanceRecord",
                       let property = userInfo["property"] as? String,
                       property == "studentID" {
                        // This is the UUID to String migration issue
                        // Try to automatically reset the store if it's safe to do so
                        // (i.e., if there's no important data to preserve)
                        do {
                            try AppBootstrapping.resetPersistentStore()
                            // Retry creating the container with the fresh store
                            // Preserve CloudKit setting - don't disable it during recovery
                            let enableCloudKit = UserDefaults.standard.object(forKey: UserDefaultsKeys.enableCloudKitSync) as? Bool ?? true
                            let container = try makeContainer(inMemory: false, cloud: enableCloudKit)
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                            return container
                        } catch {
                            // If reset failed, show error message
                            let migrationError = NSError(
                                domain: "MariasNotebook",
                                code: 3001,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Database schema migration required. The AttendanceRecord.studentID property needs to be migrated from UUID to String format. Automatic reset failed. Please use 'Reset Local Database' manually to resolve this."
                                ]
                            )
                            AppErrorHandling.handleDatabaseInitError(migrationError)
                        }
                    } else {
                        AppErrorHandling.handleDatabaseInitError(error)
                    }
                } else {
                    AppErrorHandling.handleDatabaseInitError(error)
                }
            } else {
                AppErrorHandling.handleDatabaseInitError(error)
            }
            
            // As a last resort, try to create an in-memory container
            // This allows the app to show the blocking error view even if persistent storage fails
            // NOTE: If SwiftData asserts internally here, we cannot catch it
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let fallbackContainer = try ModelContainer(for: schema, configurations: config)
                // Use safe string representation
                let errorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set("Persistent storage failed. Using temporary in-memory container. Original error: \(errorDesc)", forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return fallbackContainer
            } catch let finalError {
                // Set the error so the UI can display it
                AppErrorHandling.handleCriticalDatabaseInitError(
                    originalError: error,
                    finalError: finalError,
                    errorCode: 5001
                )
                
                // At this point, we cannot create a container with the actual persistent store.
                // As a fallback, create an in-memory container with the full schema so the app can show the error UI
                // without crashing when code attempts to fetch entities like NonSchoolDay.
                // This is a workaround - the error UI doesn't actually need a real container, but SwiftUI's
                // .modelContainer() modifier requires a non-optional ModelContainer.
                do {
                    let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    let fallbackContainer = try ModelContainer(for: schema, configurations: fallbackConfig)
                    
                    // Set the error so the UI can display it
                    AppErrorHandling.handleCriticalDatabaseInitError(
                        originalError: error,
                        finalError: finalError,
                        errorCode: 5001
                    )
                    
                    return fallbackContainer
                } catch let fallbackContainerError {
                    // Even creating an in-memory fallback container failed - this should never happen
                    // Set error state instead of crashing so user can recover
                    AppErrorHandling.handleCriticalDatabaseInitError(
                        originalError: error,
                        finalError: finalError,
                        emptyContainerError: fallbackContainerError,
                        errorCode: 5002
                    )
                    // We still need to return something, so rethrow and let the caller handle it
                    // The caller (sharedModelContainer) will catch this and handle it
                    if let criticalError = AppBootstrapping.initError as NSError? {
                        throw criticalError
                    } else {
                        throw fallbackContainerError
                    }
                }
            }
        }
    }
    
    // MARK: - Shared Model Container
    
    /// Retrieves or creates the shared model container.
    /// This property manages lazy initialization and error handling for the container.
    @MainActor
    static func getSharedModelContainer() -> ModelContainer {
        if let existing = _sharedModelContainer {
            return existing
        }
        
        // Signal that we're initializing the container (this is what takes time)
        AppBootstrapper.shared.setState(.initializingContainer)
        
        // CRITICAL: If you see a crash at this line (calling createModelContainer()),
        // SwiftData is asserting internally during schema processing.
        // 
        // This means there's a problem with the schema definition itself:
        // - Check the crash log for the exact SwiftData assertion message
        // - Look for duplicate entity names in AppSchema.schema
        // - Verify all @Relationship annotations have matching inverses
        // - Check for invalid property types or annotations
        //
        // NOTE: We cannot catch SwiftData's internal assertions - they crash immediately.

        do {
            let containerStart = Date()
            let logger = Logger.app(category: "Container")
            logger.info("ModelContainer: Starting initialization...")
            
            let container = try AppBootstrapping.createModelContainer()
            
            logger.info("ModelContainer: Creation completed in \(String(format: "%.3f", Date().timeIntervalSince(containerStart)))s")
            
            // Configure SQLite to suppress detached signature errors
            AppBootstrapping.configureSQLiteToSuppressDetachedSignatureErrors(for: container)
            _sharedModelContainer = container
            
            // Reset state to idle so bootstrap can start
            AppBootstrapper.shared.setState(.idle)
            
            logger.info("ModelContainer: Total initialization time: \(String(format: "%.3f", Date().timeIntervalSince(containerStart)))s")
            return container
        } catch {
            // This should never be reached if createModelContainer handles all errors properly,
            // but we include it as a safety net
            let errorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
            let unexpectedError = NSError(
                domain: "MariasNotebook",
                code: 6000,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected error during container initialization: \(errorDesc)"]
            )
            AppBootstrapping.initError = unexpectedError
            DatabaseErrorCoordinator.shared.setError(unexpectedError, details: errorDesc)
            
            // Create an in-memory container with full schema so the app can show the error UI
            // without crashing when code attempts to fetch entities like NonSchoolDay.
            // This is a last resort fallback.
            do {
                let fallbackSchema = AppSchema.schema
                let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                let fallbackContainer = try ModelContainer(for: fallbackSchema, configurations: fallbackConfig)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set(unexpectedError.localizedDescription, forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return fallbackContainer
            } catch {
                // If even this fails, we have no choice but to crash
                // This should never happen in practice
                fatalError("CRITICAL: Cannot create any container, including fallback. System failure: \(errorDesc)")
            }
        }
    }
    
    // MARK: - App Initialization
    
    /// Performs initial app setup tasks.
    /// This includes environment configuration, performance monitoring, and cleanup tasks.
    static func performInitialSetup() {
        // Disable CloudKit during tests to avoid entitlement-related crashes.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)
        }

        // Start monitoring main thread for stutters (blocking > 100ms)
        // This runs in all build configurations (Debug and Release)
        PerformanceLogger.startStutterDetection()
        
        #if os(macOS)
        if let icon = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif
        
        // Configure SQLite environment to suppress detached signature logging errors
        // This attempts to prevent errors about /private/var/db/DetachedSignatures
        // which occurs when SQLite tries to access a system directory that doesn't exist.
        // 
        // Note: These errors are harmless and may still appear if SQLite initializes before
        // this code runs or doesn't respect the environment variable. However, setting it
        // early in app initialization provides the best chance of suppression.
        // 
        // Error example:
        // "cannot open file at line 51043 of [f0ca7bba1c]"
        // "os_unix.c:51043: (2) open(/private/var/db/DetachedSignatures) - No such file or directory"
        setenv("SQLITE_DISABLE_SIGNATURE_LOGGING", "1", 0)
        
        // Cleanup: remove legacy Beta flag now that Engagement Lifecycle is always on
        UserDefaults.standard.removeObject(forKey: "useEngagementLifecycle")
        
        // NOTE: CoreData+CloudKit error messages and WAL maintenance logs in console
        // SwiftData uses Core Data internally, and during CloudKit initialization,
        // it creates temporary stores (file:///dev/null) that get torn down, causing harmless error messages.
        // These errors (like "store was removed from coordinator" and error code 134060)
        // are expected during initialization and don't affect functionality.
        //
        // The CloudKitSyncStatusService has been configured to ignore these expected teardowns
        // by delaying observer setup for 2 seconds and implementing a 15-second startup grace period.
        // This prevents false "offline" reports in the UI while still monitoring for real connection issues.
        //
        // Additionally, in Debug builds, you may see verbose SQLite logs including:
        // - WAL checkpoint operations
        // - PostSaveMaintenance operations
        // - SQL query execution details
        // These are normal Core Data/SQLite maintenance operations and do not indicate errors.
        // They are enabled by default in Debug builds via Xcode's diagnostics and cannot be
        // suppressed from Swift code. These logs can be safely ignored.
        
        #if DEBUG
        // TEST: Simulate database initialization failure for testing recovery flow
        // Set this UserDefaults key to trigger a simulated failure
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.debugSimulateDatabaseInitFailure) {
            let testError = NSError(
                domain: "MariasNotebook",
                code: 9999,
                userInfo: [
                    NSLocalizedDescriptionKey: "DEBUG: Simulated database initialization failure. This is a test error to verify the recovery UI. Clear the 'DEBUG_SimulateDatabaseInitFailure' UserDefaults flag to restore normal operation."
                ]
            )
            AppBootstrapping.initError = testError
            DatabaseErrorCoordinator.shared.setError(testError, details: "This is a simulated error for testing purposes.")
        }
        #endif
    }
}
