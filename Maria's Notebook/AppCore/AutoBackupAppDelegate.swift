#if os(macOS)
import AppKit
import CoreData
import SwiftUI

/// AppDelegate to handle automatic backups on app termination
@MainActor
final class AutoBackupAppDelegate: NSObject, NSApplicationDelegate {
    private var coreDataStack: CoreDataStack?
    private var autoBackupManager: AutoBackupManager?

    func setCoreDataStack(_ stack: CoreDataStack) {
        self.coreDataStack = stack
        // Create AutoBackupManager with BackupService
        self.autoBackupManager = AutoBackupManager(backupService: BackupService())
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Perform automatic backup before app quits
        guard let coreDataStack,
              let autoBackupManager = autoBackupManager else { return }

        let viewContext = coreDataStack.viewContext
        
        // Run backup on main thread (app is quitting, blocking is acceptable)
        // Since AutoBackupManager is @MainActor, we need to run this on the main thread
        // Use RunLoop to process the async task while waiting
        let semaphore = DispatchSemaphore(value: 0)
        
        Task { @MainActor in
            await autoBackupManager.performBackupOnQuit(viewContext: viewContext)
            semaphore.signal()
        }
        
        // Wait up to 30 seconds for backup to complete, processing RunLoop events
        // Use 1.0 second intervals to reduce CPU usage while still processing RunLoop events
        let timeout = Date().addingTimeInterval(30)
        let checkInterval: TimeInterval = 1.0
        while semaphore.wait(timeout: .now() + checkInterval) == .timedOut {
            if Date() > timeout {
                break // Timeout reached
            }
            // Process RunLoop events to allow backup task to progress
            RunLoop.current.run(until: Date(timeIntervalSinceNow: checkInterval))
        }
    }
}
#endif
