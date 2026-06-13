#if os(iOS)
import Foundation
import BackgroundTasks
import CoreData
import OSLog
import UIKit

/// Registers and schedules the periodic background backup task.
///
/// Two triggers keep iPhone/iPad users protected without relying on the app
/// staying open (the scheduled-interval loop can't run while suspended):
///   1. Scene-phase: every move to the background runs a change-gated backup
///      under a short `UIApplication` background task assertion.
///   2. `BGProcessingTask`: iOS opportunistically grants longer windows
///      (typically overnight) for a backup even when the app wasn't opened.
///
/// Both funnel into `AutoBackupManager.performBackgroundBackup`, which skips
/// in milliseconds when persistent history shows no changes.
@MainActor
enum BackupBackgroundTaskManager {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "DanielSDeBerry.MariasNoteBook.backup"
    private static let logger = Logger.backup

    /// Registers the launch handler. Must run before the app finishes
    /// launching — called from `MariasNotebookApp.init()`.
    static func register(dependencies: AppDependencies, coreDataStack: CoreDataStack) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: .main
        ) { task in
            // Delivered on the main queue (`using: .main`), so this is sound.
            MainActor.assumeIsolated {
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                handle(processingTask, dependencies: dependencies, coreDataStack: coreDataStack)
            }
        }
    }

    /// Submits the next background backup request. Safe to call repeatedly —
    /// resubmitting the same identifier replaces the pending request.
    ///
    /// Uses the iOS 27 `submitTaskRequest(_:)` async API (the throwing
    /// `submit(_:)` was deprecated). Suspends rather than blocking, so it's
    /// safe to await from the main actor.
    static func schedule() async {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        // Backups are change-gated, so a generous floor is fine: the
        // scene-phase trigger covers active use; this covers neglected devices.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)

        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } catch {
            // Expected on the simulator, which doesn't run BGTaskScheduler.
            logger.info(
                "Background backup task not scheduled: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func handle(
        _ task: BGProcessingTask,
        dependencies: AppDependencies,
        coreDataStack: CoreDataStack
    ) {
        let backupWork = Task { @MainActor in
            // Keep the chain alive for the next opportunity.
            await schedule()
            await dependencies.autoBackupManager.performBackgroundBackup(
                viewContext: coreDataStack.viewContext
            )
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            backupWork.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

/// Holds a `UIApplication` background task assertion across an async backup
/// so the scene-phase trigger gets time to finish after the app backgrounds.
@MainActor
final class BackgroundTaskAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin(named name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
