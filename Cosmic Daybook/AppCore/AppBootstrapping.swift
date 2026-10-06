//
//  AppBootstrapping.swift
//  Cosmic Daybook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import CoreData
import OSLog

/// Handles all app initialization, database setup, and lifecycle management.
final class AppBootstrapping {

    /// Hosted unit tests launch the app process, but they should not also start
    /// the full SwiftUI/Core Data bootstrap while tests create isolated stores.
    /// Keeping this check in one place also matches the existing CloudKit test
    /// safeguard below.
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Shared Instance

    /// CDTrackEntity initialization errors to show in the UI
    static var initError: Error?

    /// Core Data stack with NSPersistentCloudKitContainer: set once its
    /// stores are open (`sharedCoreDataStack()`), or to the in-memory stack
    /// behind the database-error screen when they can't be. Nil while they
    /// are still opening, off the main thread.
    static var _sharedCoreDataStack: CoreDataStack?

    /// Runtime-only CloudKit disable flag used during XCTest runs.
    /// This prevents tests from touching CloudKit without persisting the disabled state.
    static var disableCloudKitForCurrentLaunch: Bool = false

    // MARK: - Store Management

    #if DEBUG
    /// Arms a reset of the local database for the next launch
    /// (`DatabaseInitializationService.armLocalDatabaseResetInDebug`).
    static func armLocalDatabaseResetInDebug() -> Bool {
        DatabaseInitializationService.armLocalDatabaseResetInDebug()
    }
    
    #if os(macOS)
    /// Shows a confirmation dialog and resets the local database if confirmed.
    /// This is a DEBUG-only function that requires user confirmation before resetting.
    static func requestResetLocalDatabaseWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Reset Local Database?"
        alert.informativeText = "This removes the notebook from this device when the app next opens."
            + " Your notebook in iCloud stays and downloads again. The app quits now."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset").hasDestructiveAction = true

        guard alert.runModal() == .alertSecondButtonReturn else { return }
        guard armLocalDatabaseResetInDebug() else {
            let refused = NSAlert()
            refused.messageText = "Can't Reset While Sync Is Off"
            refused.informativeText = "iCloud sync is off, so this device has the only copy of the notebook."
                + " Nothing was changed."
            refused.runModal()
            return
        }
        // Quit; the next launch removes the stores before anything opens them.
        NSApplication.shared.terminate(nil)
    }
    #endif
    #endif
    
    static func storeFileURL() -> URL {
        DatabaseInitializationService.storeFileURL()
    }

    // MARK: - App Initialization
    
    /// Performs initial app setup tasks.
    /// This includes environment configuration, performance monitoring, and cleanup tasks.
    static func performInitialSetup() {
        // Default CloudKit sync to enabled unless explicitly turned off by the user.
        UserDefaults.standard.register(defaults: [UserDefaultsKeys.enableCloudKitSync: true])

        // Disable CloudKit during tests to avoid entitlement-related crashes.
        if isRunningUnitTests {
            disableCloudKitForCurrentLaunch = true
        }

        // One school year on every device: adopt the synced start date and counter mode
        // before anything reads them (the Mac seeds an empty iCloud). Never under tests.
        SchoolYearSync.start()
        // Which rules this build keeps the classroom share by, so a device's build can be
        // checked before last year's records are taken out of the share.
        Logger.classroomSharing.notice(
            "Classroom share scope v\(ClassroomShareScope.version, privacy: .public): this school year only"
        )

        // Start monitoring main thread for stutters (blocking > 100ms)
        // This runs in all build configurations (Debug and Release)
        PerformanceLogger.startStutterDetection()
        
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

        // NOTE: Core Data+CloudKit error messages and WAL maintenance logs in console
        // During CloudKit initialization,
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
    }

    #if DEBUG
    /// TEST: Simulates a database initialization failure, for trying the
    /// recovery flow: set the UserDefaults key and relaunch. Applied once the
    /// real stores are open (`openSharedStack`), so the error screen's
    /// restore finds them open and refuses, rather than racing a load still
    /// under way.
    static func simulateDatabaseFailureIfRequested() {
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.debugSimulateDatabaseInitFailure) {
            let testError = NSError(
                domain: "CosmicDaybook",
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
    }
    #endif
}
