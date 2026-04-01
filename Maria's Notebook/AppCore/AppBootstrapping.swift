//
//  AppBootstrapping.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import CoreData
import OSLog

/// Handles all app initialization, database setup, and lifecycle management.
@MainActor
final class AppBootstrapping {

    // MARK: - Shared Instance

    /// CDTrackEntity initialization errors to show in the UI
    @MainActor
    static var initError: Error?

    /// Core Data stack with NSPersistentCloudKitContainer.
    /// Initialized on first access via the static factory method.
    @MainActor
    static var _sharedCoreDataStack: CoreDataStack?

    // Legacy _sharedModelContainer removed — SwiftData migration complete.

    /// Runtime-only CloudKit disable flag used during XCTest runs.
    /// This prevents tests from touching CloudKit without persisting the disabled state.
    @MainActor
    static var disableCloudKitForCurrentLaunch: Bool = false
    
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
        alert.informativeText = "This deletes local data on this device."
            + " CloudKit data is preserved and will re-sync after restart."
            + " The app will restart automatically."
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

    /// Attempts to migrate CDAttendanceRecord.studentID from UUID to String.
    /// Returns true if migration was successful or not needed.
    @discardableResult
    static func attemptAttendanceRecordMigrationIfNeeded() -> Bool {
        DatabaseInitializationService.attemptAttendanceRecordMigrationIfNeeded()
    }

    /// Configures SQLite to suppress detached signature logging errors.
    static func configureSQLiteToSuppressDetachedSignatureErrors(for container: NSPersistentContainer) {
        DatabaseInitializationService.configureSQLiteToSuppressDetachedSignatureErrors(for: container)
    }
    
    // MARK: - App Initialization
    
    /// Performs initial app setup tasks.
    /// This includes environment configuration, performance monitoring, and cleanup tasks.
    static func performInitialSetup() {
        // Default CloudKit sync to enabled unless explicitly turned off by the user.
        UserDefaults.standard.register(defaults: [UserDefaultsKeys.enableCloudKitSync: true])

        // Disable CloudKit during tests to avoid entitlement-related crashes.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            disableCloudKitForCurrentLaunch = true
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
        // CDNote: These errors are harmless and may still appear if SQLite initializes before
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
                    NSLocalizedDescriptionKey: "DEBUG: Simulated database initialization failure."
                        + " This is a test error to verify the recovery UI."
                        + " Clear the 'DEBUG_SimulateDatabaseInitFailure'"
                        + " UserDefaults flag to restore normal operation."
                ]
            )
            AppBootstrapping.initError = testError
            DatabaseErrorCoordinator.shared.setError(
                testError,
                details: "This is a simulated error for testing purposes."
            )
        }
        #endif
    }
}
