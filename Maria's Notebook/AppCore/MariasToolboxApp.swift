//
//  MariasToolboxApp.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import SwiftData
import CoreData
import OSLog
#if os(macOS)
import AppKit
#endif

@main
struct MariasToolboxApp: App {
    // MARK: - UserDefaults Keys (deprecated - use UserDefaultsKeys instead)
    @available(*, deprecated, message: "Use UserDefaultsKeys instead")
    static let useInMemoryFlagKey = UserDefaultsKeys.useInMemoryStoreOnce
    @available(*, deprecated, message: "Use UserDefaultsKeys instead")
    static let ephemeralSessionFlagKey = UserDefaultsKeys.ephemeralSessionFlag
    @available(*, deprecated, message: "Use UserDefaultsKeys instead")
    static let lastStoreErrorDescriptionKey = UserDefaultsKeys.lastStoreErrorDescription
    @available(*, deprecated, message: "Use UserDefaultsKeys instead")
    static let allowLocalStoreFallbackKey = UserDefaultsKeys.allowLocalStoreFallback
    @available(*, deprecated, message: "Use UserDefaultsKeys instead")
    static let enableCloudKitKey = UserDefaultsKeys.enableCloudKitSync
    @available(*, deprecated, message: "Use UserDefaultsKeys instead")
    static let cloudKitActiveKey = UserDefaultsKeys.cloudKitActive
    
    /// Returns the CloudKit container identifier from entitlements
    /// This must match the container ID in the entitlements file
    static func getCloudKitContainerID() -> String? {
        CloudKitConfigurationService.getContainerID()
    }

    /// Returns a summary of CloudKit sync status
    static func getCloudKitStatus() -> (enabled: Bool, active: Bool, containerID: String) {
        let status = CloudKitConfigurationService.getStatus()
        return (enabled: status.enabled, active: status.active, containerID: status.containerID)
    }
    
    // MARK: - Error Handling Helpers

    /// Centralized error handling for database initialization failures.
    /// Delegates to DatabaseInitializationService.
    @MainActor
    static func handleDatabaseInitError(_ error: Error, description: String? = nil) {
        DatabaseInitializationService.handleDatabaseInitError(error, description: description)
    }

    /// Handles critical database initialization failure with multiple error contexts.
    /// Delegates to DatabaseInitializationService.
    @MainActor
    static func handleCriticalDatabaseInitError(
        originalError: Error,
        finalError: Error? = nil,
        emptyContainerError: Error? = nil,
        errorCode: Int = 5002
    ) {
        DatabaseInitializationService.handleCriticalDatabaseInitError(
            originalError: originalError,
            finalError: finalError,
            emptyContainerError: emptyContainerError,
            errorCode: errorCode
        )
    }
    
    // Track initialization errors to show in the UI
    @MainActor
    static var initError: Error?
    
    // Logger for reset operations
    private static let resetLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "Reset")

    @StateObject private var saveCoordinator = SaveCoordinator()
    @StateObject private var bootstrapper = AppBootstrapper.shared
    @StateObject private var restoreCoordinator = RestoreCoordinator()
    @StateObject private var appRouter = AppRouter.shared
    @StateObject private var databaseErrorCoordinator = DatabaseErrorCoordinator.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AutoBackupAppDelegate
    #endif

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
        
        // #if DEBUG
        // print("SwiftData: Starting container initialization...")
        // #endif
        
        // Get schema - if SwiftData asserts here, it's a schema definition problem
        let schema = AppSchema.schema
        // #if DEBUG
        // print("SwiftData: Schema accessed successfully")
        // #endif
        
        let useInMemory = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useInMemoryStoreOnce)
        let _ = UserDefaults.standard.bool(forKey: UserDefaultsKeys.allowLocalStoreFallback)
        
        // Helper to create container with defensive error handling
        func makeContainer(inMemory: Bool, url: URL? = nil, cloud: Bool = false) throws -> ModelContainer {
            // #if DEBUG
            // print("SwiftData: Attempting to create container (inMemory: \(inMemory), cloud: \(cloud))...")
            // #endif
            do {
                if inMemory {
                    let config = ModelConfiguration(isStoredInMemoryOnly: true)
                    // SwiftData may assert here if the schema is invalid
                    let container = try ModelContainer(for: schema, configurations: config)
                    // #if DEBUG
                    // print("SwiftData: Successfully created in-memory container")
                    // #endif
                    return container
                } else if cloud {
                    // Use the container ID from entitlements (must match entitlements file)
                    let storeURL = url ?? MariasToolboxApp.storeFileURL()
                    
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
                        // #if DEBUG
                        // print("SwiftData: iCloud is not available (not signed in). Skipping CloudKit container creation.")
                        // #endif
                        // Store error state
                        let errorMessage = "Not signed into iCloud. Please sign in to System Settings > Apple ID > iCloud to enable sync."
                        UserDefaults.standard.set(errorMessage, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                        // Fall back to local store
                        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                        let container = try ModelContainer(for: schema, configurations: config)
                        return container
                    }
                    
                    guard let containerID = MariasToolboxApp.getCloudKitContainerID() else {
                        // #if DEBUG
                        // print("SwiftData: Missing CloudKit container identifier. Falling back to local store without CloudKit.")
                        // #endif
                        let errorMessage = "Missing CloudKit container identifier. CloudKit sync cannot be initialized."
                        UserDefaults.standard.set(errorMessage, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                        let container = try ModelContainer(for: schema, configurations: config)
                        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                        return container
                    }

                    #if swift(>=6.0)
                    if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                        // #if DEBUG
                        // print("SwiftData: CloudKit configuration:")
                        // print("  - Container ID: \(containerID)")
                        // print("  - Store URL: \(storeURL.path)")
                        // print("  - Database: Private")
                        // #endif
                        do {
                            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .private(containerID))
                            let container = try ModelContainer(for: schema, configurations: config)
                            // #if DEBUG
                            // print("SwiftData: ✅ CloudKit container created successfully!")
                            // print("SwiftData: CloudKit sync is now active. Changes will sync across devices.")
                            // print("SwiftData: Note: CoreData+CloudKit error messages about 'store was removed' are expected")
                            // print("SwiftData:   and harmless - they occur during SwiftData's internal initialization.")
                            // #endif
                            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
                            // Clear any previous error since CloudKit is now active
                            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                            return container
                        } catch {
                            // CloudKit initialization failed - log detailed error and fall back to local store
                            // #if DEBUG
                            // print("SwiftData: ⚠️ CloudKit initialization failed: \(error)")
                            // if let nsError = error as NSError? {
                            //     print("SwiftData: Error domain: \(nsError.domain), code: \(nsError.code)")
                            //     print("SwiftData: Error userInfo: \(nsError.userInfo)")
                            // }
                            // print("SwiftData: Falling back to local store without CloudKit sync.")
                            // #endif
                            // Store the error for display in the UI
                            let errorDescription = (error as NSError?)?.localizedDescription ?? String(describing: error)
                            if let nsError = error as NSError? {
                                let userInfo = nsError.userInfo
                                // Try to get more detailed error information
                                var detailedError = errorDescription
                                if let underlyingError = userInfo[NSUnderlyingErrorKey] as? NSError {
                                    detailedError = underlyingError.localizedDescription
                                } else if let errorMessage = userInfo[NSLocalizedDescriptionKey] as? String {
                                    detailedError = errorMessage
                                }
                                UserDefaults.standard.set(detailedError, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                            } else {
                                UserDefaults.standard.set(errorDescription, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                            }
                            // Fall back to local store
                            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                            let container = try ModelContainer(for: schema, configurations: config)
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                            return container
                        }
                    } else {
                        throw NSError(domain: "MariasNotebook", code: 2002, userInfo: [NSLocalizedDescriptionKey: "CloudKit requires iOS 17 / macOS 14 or later for SwiftData."])
                    }
                    #else
                    if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                        // #if DEBUG
                        // print("SwiftData: CloudKit configuration:")
                        // print("  - Container ID: \(containerID)")
                        // print("  - Store URL: \(storeURL.path)")
                        // print("  - Database: Private")
                        // #endif
                        do {
                            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .private(containerID))
                            let container = try ModelContainer(for: schema, configurations: config)
                            // #if DEBUG
                            // print("SwiftData: ✅ CloudKit container created successfully!")
                            // print("SwiftData: CloudKit sync is now active. Changes will sync across devices.")
                            // print("SwiftData: Note: CoreData+CloudKit error messages about 'store was removed' are expected")
                            // print("SwiftData:   and harmless - they occur during SwiftData's internal initialization.")
                            // #endif
                            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
                            // Clear any previous error since CloudKit is now active
                            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                            return container
                        } catch {
                            // CloudKit initialization failed - log detailed error and fall back to local store
                            // #if DEBUG
                            // print("SwiftData: ⚠️ CloudKit initialization failed: \(error)")
                            // if let nsError = error as NSError? {
                            //     print("SwiftData: Error domain: \(nsError.domain), code: \(nsError.code)")
                            //     print("SwiftData: Error userInfo: \(nsError.userInfo)")
                            // }
                            // print("SwiftData: Falling back to local store without CloudKit sync.")
                            // #endif
                            // Store the error for display in the UI
                            let errorDescription = (error as NSError?)?.localizedDescription ?? String(describing: error)
                            if let nsError = error as NSError? {
                                let userInfo = nsError.userInfo
                                // Try to get more detailed error information
                                var detailedError = errorDescription
                                if let underlyingError = userInfo[NSUnderlyingErrorKey] as? NSError {
                                    detailedError = underlyingError.localizedDescription
                                } else if let errorMessage = userInfo[NSLocalizedDescriptionKey] as? String {
                                    detailedError = errorMessage
                                }
                                UserDefaults.standard.set(detailedError, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                            } else {
                                UserDefaults.standard.set(errorDescription, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                            }
                            // Fall back to local store
                            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                            let container = try ModelContainer(for: schema, configurations: config)
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                            return container
                        }
                    } else {
                        throw NSError(domain: "MariasNotebook", code: 2002, userInfo: [NSLocalizedDescriptionKey: "CloudKit requires iOS 17 / macOS 14 or later for SwiftData."])
                    }
                    #endif
                } else {
                    // Explicitly disable CloudKit for SwiftData (we use CloudDocuments for file storage instead)
                    let config = ModelConfiguration(
                        url: url ?? MariasToolboxApp.storeFileURL(),
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
            // Attempt migration before opening store (if needed)
            _ = MariasToolboxApp.attemptAttendanceRecordMigrationIfNeeded()
            
            let _ = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            if useInMemory {
                // #if DEBUG
                // print("SwiftData: Creating in-memory store...")
                // #endif
                // We already validated the schema, so this should work
                let container = try makeContainer(inMemory: true)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set("Using temporary in-memory store on next launch.", forKey: UserDefaultsKeys.lastStoreErrorDescription)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
                // #if DEBUG
                // print("SwiftData: Using in-memory store.")
                // #endif
                return container
            } else {
                // Validate store file before attempting to open
                let storeURL = MariasToolboxApp.storeFileURL()
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
                    // #if DEBUG
                    // print("SwiftData: Store file exists at \(storeURL.path)")
                    // #endif
                } else {
                    // #if DEBUG
                    // print("SwiftData: Store file does not exist, will create new store at \(storeURL.path)")
                    // #endif
                }
                
                // CloudKit compatibility: All model fixes are complete. Enable CloudKit by default.
                // Users can disable it via the settings toggle if needed.
                let enableCloudKit = UserDefaults.standard.object(forKey: UserDefaultsKeys.enableCloudKitSync) as? Bool ?? true
                // #if DEBUG
                // if enableCloudKit {
                //     print("SwiftData: Creating CloudKit-enabled container...")
                // } else {
                //     print("SwiftData: Creating local storage container (CloudKit disabled - set '\(UserDefaultsKeys.enableCloudKitSync)' UserDefaults flag to enable)...")
                // }
                // #endif
                let container = try makeContainer(inMemory: false, cloud: enableCloudKit)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                if enableCloudKit {
                    // cloudKitActiveKey is set in makeContainer when CloudKit is successfully initialized
                    // #if DEBUG
                    // print("SwiftData: ✅ Using CloudKit-enabled storage.")
                    // #endif
                } else {
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                    // #if DEBUG
                    // print("SwiftData: Using local storage.")
                    // #endif
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
                            try MariasToolboxApp.resetPersistentStore()
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
                            MariasToolboxApp.handleDatabaseInitError(migrationError)
                        }
                    } else {
                        MariasToolboxApp.handleDatabaseInitError(error)
                    }
                } else {
                    MariasToolboxApp.handleDatabaseInitError(error)
                }
            } else {
                MariasToolboxApp.handleDatabaseInitError(error)
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
                MariasToolboxApp.handleCriticalDatabaseInitError(
                    originalError: error,
                    finalError: finalError,
                    errorCode: 5001
                )
                
                // At this point, we cannot create a container with the actual schema.
                // As an absolute last resort, try to create an empty container just so the app can show the error UI.
                // This is a workaround - the error UI doesn't actually need a real container, but SwiftUI's
                // .modelContainer() modifier requires a non-optional ModelContainer.
                do {
                    let emptySchema = Schema([])
                    let emptyConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    let emptyContainer = try ModelContainer(for: emptySchema, configurations: emptyConfig)
                    
                    // Set the error so the UI can display it
                    MariasToolboxApp.handleCriticalDatabaseInitError(
                        originalError: error,
                        finalError: finalError,
                        errorCode: 5001
                    )
                    
                    return emptyContainer
                } catch let emptyContainerError {
                    // Even creating an empty container failed - this should never happen
                    // Set error state instead of crashing so user can recover
                    MariasToolboxApp.handleCriticalDatabaseInitError(
                        originalError: error,
                        finalError: finalError,
                        emptyContainerError: emptyContainerError,
                        errorCode: 5002
                    )
                    // We still need to return something, so rethrow and let the caller handle it
                    // The caller (sharedModelContainer) will catch this and handle it
                    if let criticalError = MariasToolboxApp.initError as NSError? {
                        throw criticalError
                    } else {
                        throw emptyContainerError
                    }
                }
            }
        }
    }
    
    /// Model container for SwiftData.
    /// Initialized on first access via the static factory method.
    /// If SwiftData asserts internally during schema processing, we cannot catch it.
    @MainActor
    private static var _sharedModelContainer: ModelContainer?
    
    @MainActor
    var sharedModelContainer: ModelContainer {
        if let existing = MariasToolboxApp._sharedModelContainer {
            return existing
        }
        
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
        // #if DEBUG
        // print("SwiftData: Accessing sharedModelContainer - will create container now...")
        // print("SwiftData: If crash occurs here, check schema definition in AppSchema.swift")
        // #endif
        
        do {
            let container = try MariasToolboxApp.createModelContainer()
            // Configure SQLite to suppress detached signature errors
            MariasToolboxApp.configureSQLiteToSuppressDetachedSignatureErrors(for: container)
            MariasToolboxApp._sharedModelContainer = container
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
            MariasToolboxApp.initError = unexpectedError
            DatabaseErrorCoordinator.shared.setError(unexpectedError, details: errorDesc)
            
            // Create an empty container so the app can show the error UI
            // This is a last resort fallback
            do {
                let emptySchema = Schema([])
                let emptyConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                let emptyContainer = try ModelContainer(for: emptySchema, configurations: emptyConfig)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set(unexpectedError.localizedDescription, forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return emptyContainer
            } catch {
                // If even this fails, we have no choice but to crash
                // This should never happen in practice
                fatalError("CRITICAL: Cannot create any container, including empty one. System failure: \(errorDesc)")
            }
        }
    }

    init() {
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
        // it creates temporary stores that get torn down, causing harmless error messages.
        // These errors (like "store was removed from coordinator" and "file:///dev/null")
        // are expected during initialization and don't affect functionality.
        // The container is successfully created (see "✅ CloudKit container created successfully!" message).
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
            MariasToolboxApp.initError = testError
            DatabaseErrorCoordinator.shared.setError(testError, details: "This is a simulated error for testing purposes.")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("", id: "mainWindow") {
            Group {
                // Show database error view if there's an initialization error
                if databaseErrorCoordinator.error != nil || MariasToolboxApp.initError != nil {
                    DatabaseErrorView(errorCoordinator: databaseErrorCoordinator, appRouter: appRouter)
                } else {
                    // NORMAL APP FLOW
                    if bootstrapper.state == .ready {
                        Group {
                            if restoreCoordinator.isRestoring {
                                VStack(spacing: 20) {
                                    ProgressView().controlSize(.large)
                                    Text("Restoring data…")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.clear)
                            } else {
                                RootView()
                                    .environment(\.calendar, AppCalendar.shared)
                                    .environment(\.appRouter, appRouter)
                                    .environmentObject(saveCoordinator)
                                    .environmentObject(restoreCoordinator)
                            }
                        }
                    } else {
                        // Loading / Splash Screen
                        VStack(spacing: 20) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Preparing Database...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                    }
                }
            }
            .task {
                // Sync initError to error coordinator if not already set
                if databaseErrorCoordinator.error == nil, let error = MariasToolboxApp.initError {
                    databaseErrorCoordinator.setError(error)
                }
                
                // Only bootstrap if the store loaded successfully
                if MariasToolboxApp.initError == nil {
                    #if os(macOS)
                    appDelegate.setModelContainer(sharedModelContainer)
                    #endif
                    await bootstrapper.bootstrap(modelContainer: sharedModelContainer)
                }
            }
            #if os(macOS)
            .modifier(OpenWindowOnNotificationModifier())
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 800, height: 700)
        #endif
        .modelContainer(sharedModelContainer)
        .commands {
            // 1. STANDARD "NEW" ITEMS (File > New)
            // Consolidates all creation actions into the standard location
            CommandGroup(replacing: .newItem) {
                #if os(macOS)
                Button("New Window") {
                    NotificationCenter.default.post(name: .openNewWindow, object: nil)
                }
                Divider()
                #endif
                
                Button("New Lesson") { appRouter.requestNewLesson() }
                    .keyboardShortcut("n", modifiers: [.command])
                
                Button("New Student") { appRouter.requestNewStudent() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("New Work…") { appRouter.requestNewWork() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }

            // 2. STANDARD "IMPORT/EXPORT" ITEMS (File > Import)
            // Moves Imports, Backups, and Restores here
            CommandGroup(replacing: .importExport) {
                Section {
                    Button("Import Lessons…") { appRouter.requestImportLessons() }
                        .keyboardShortcut("i", modifiers: [.command])
                    
                    Button("Import Students…") { appRouter.requestImportStudents() }
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                }
                
                Section {
                    Button("Create Backup") { appRouter.requestCreateBackup() }
                        .keyboardShortcut("b", modifiers: [.command])
                    
                    Button("Restore Data…") { appRouter.requestRestoreBackup() }
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                }
            }

            // 3. GO MENU (Navigation)
            // Dedicated menu for navigating between app sections
            CommandMenu("Go") {
                Button("Today") { appRouter.navigateTo(.today) }
                    .keyboardShortcut("1", modifiers: .command)

                Button("Presentations") { appRouter.navigateTo(.planningAgenda) }
                    .keyboardShortcut("2", modifiers: .command)

                Button("Students") { appRouter.navigateTo(.students) }
                    .keyboardShortcut("3", modifiers: .command)

                Button("Lessons") { appRouter.navigateTo(.lessons) }
                    .keyboardShortcut("4", modifiers: .command)

                Button("Logs") { appRouter.navigateTo(.logs) }
                    .keyboardShortcut("5", modifiers: .command)

                Button("Attendance") { appRouter.navigateTo(.attendance) }
                    .keyboardShortcut("6", modifiers: .command)
            }
            
            // 4. STANDARD SETTINGS (App Menu)
            // Maps the standard macOS "Settings..." menu item (Cmd+,) to your Settings tab
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appRouter.navigateTo(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // 5. HELP & TROUBLESHOOTING (Help Menu)
            // Hides the "junk" inside a submenu in Help, or you can delete it entirely
            CommandGroup(replacing: .help) {
                // Keeps the default search bar
                Button("\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App") Help") {
                    // Action to open help
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                // Move all technical toggles into a submenu to keep the top bar clean
                Menu("Troubleshooting") {
                    #if os(macOS)
                    Toggle("Allow Local Store Fallback", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.allowLocalStoreFallback) },
                        set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.allowLocalStoreFallback) }
                    ))
                    Toggle("Enable CloudKit Sync", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync) },
                        set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.enableCloudKitSync) }
                    ))
                    #endif
                    
                    Button("Use In-Memory Store Next Launch") {
                        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
                    }
                    
                    #if DEBUG
                    Divider()
                    
                    Button("Reset Local Database…", role: .destructive) {
                        #if os(macOS)
                        MariasToolboxApp.requestResetLocalDatabaseWithConfirmation()
                        #else
                        // On iOS, this would need a different approach (not available via menu)
                        try? MariasToolboxApp.resetLocalDatabaseInDebug()
                        #endif
                    }
                    #endif
                }
            }
        }

        #if os(macOS)
        WindowGroup("", id: "WorkDetailWindow", for: UUID.self) { $workID in
            if let id = workID {
                Group {
                    if restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text("Restoring data…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        ContractDetailWindowHost(workID: id)
                            .environment(\.calendar, AppCalendar.shared)
                            .environmentObject(saveCoordinator)
                            .environmentObject(restoreCoordinator)
                    }
                }
            } else {
                Text("No work selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 700)
        .modelContainer(sharedModelContainer)
        #endif
    }
}

