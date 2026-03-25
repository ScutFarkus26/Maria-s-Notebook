#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// AppDelegate to handle automatic backups on app termination
@MainActor
final class AutoBackupAppDelegate: NSObject, NSApplicationDelegate {
    private var modelContainer: ModelContainer?
    private var autoBackupManager: AutoBackupManager?
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        // Create AutoBackupManager with BackupService
        self.autoBackupManager = AutoBackupManager(backupService: BackupService())
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Perform automatic backup before app quits
        guard let modelContainer,
              let autoBackupManager = autoBackupManager else { return }
        
        let modelContext = modelContainer.mainContext
        
        // Run backup on main thread (app is quitting, blocking is acceptable)
        // Since AutoBackupManager is @MainActor, we need to run this on the main thread
        // Use RunLoop to process the async task while waiting
        let semaphore = DispatchSemaphore(value: 0)
        
        Task { @MainActor in
            await autoBackupManager.performBackupOnQuit(modelContext: modelContext)
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
