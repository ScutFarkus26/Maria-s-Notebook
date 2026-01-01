#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// AppDelegate to handle automatic backups on app termination
final class AutoBackupAppDelegate: NSObject, NSApplicationDelegate {
    private var modelContainer: ModelContainer?
    private let autoBackupManager = AutoBackupManager()
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Perform automatic backup before app quits
        guard let modelContainer = modelContainer else { return }
        
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
        let timeout = Date().addingTimeInterval(30)
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if Date() > timeout {
                break // Timeout reached
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
}
#endif

