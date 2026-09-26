#if os(iOS)
import Foundation
import BackgroundTasks
import CoreData
import OSLog
import Synchronization
import UIKit

/// Registers and schedules the periodic background backup task.
///
/// Two triggers keep iPhone/iPad users protected without relying on the app
/// staying open (the scheduled-interval loop can't run while suspended):
///   1. Scene-phase: every move to the background runs a change-gated backup
///      under a short `UIApplication` background task assertion.
///   2. `BGProcessingTask`: iOS opportunistically grants longer windows
///      (typically overnight, on a charger) for a backup even when the app
///      wasn't opened. If iPadOS ends the window early, the export stops
///      between record types and leaves no file.
///
/// Both funnel into `AutoBackupManager.performBackgroundBackup`, which skips
/// in milliseconds when persistent history shows no changes.
enum BackupBackgroundTaskManager {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "DanielSDeBerry.MariasNoteBook.backup"
    private static let logger = Logger.backup

    /// Registers the launch handler. Must run before the app finishes
    /// launching — called from `CosmicDaybookApp.init()`.
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
    static func schedule(after delay: TimeInterval = 12 * 3600) async {
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(makeRequest(after: delay))
        } catch {
            // Expected on the simulator, which doesn't run BGTaskScheduler.
            logger.info(
                "Background backup task not scheduled: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func makeRequest(after delay: TimeInterval) -> BGProcessingTaskRequest {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        // A full-store export: only on a charger (DANNY DECIDED 2026-09-25).
        // An iPad that never sits idle on one still gets the scene-phase
        // backup on every change-carrying app switch.
        request.requiresExternalPower = true
        // Backups are change-gated, so a generous floor is fine: the
        // scene-phase trigger covers active use; this covers neglected devices.
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        return request
    }

    private static func handle(
        _ task: BGProcessingTask,
        dependencies: AppDependencies,
        coreDataStack: CoreDataStack
    ) {
        task.expirationHandler = startWork({
            // Keep the chain alive for the next opportunity.
            await schedule()
            // The overnight window ignores the scene-phase gap (it is 12 h
            // apart anyway) but still waits out a hot device; ask again in an
            // hour rather than twelve when it did. When iPadOS ends the task
            // early the export stops between record types and writes nothing.
            let outcome = await dependencies.autoBackupManager.performBackgroundBackup(
                viewContext: coreDataStack.viewContext,
                enforcingMinimumGap: false,
                stopsWhenCancelled: true
            )
            if outcome == .deferredConstrained {
                await schedule(after: 3600)
            }
        }, complete: { success in
            task.setTaskCompleted(success: success)
        })
    }

    /// Starts `work` in a utility-priority task and returns the expiration
    /// handler, which cancels it. `complete` is called exactly once: with
    /// true when the work finishes first, with false when the system ends
    /// the task first.
    static func startWork(
        _ work: @escaping @MainActor () async -> Void,
        complete: @escaping (Bool) -> Void
    ) -> () -> Void {
        let gate = CompletionGate()
        // Utility: the export's encode half inherits it off the main actor.
        let running = Task(priority: .utility) {
            await work()
            if gate.claim() { complete(true) }
        }
        return makeExpirationHandler(cancelling: running, gate: gate, complete: complete)
    }

    /// Nonisolated because iPadOS may call the expiration handler on any
    /// thread; it only cancels a task, takes the gate and completes the
    /// BGTask, all of which are thread-safe.
    private nonisolated static func makeExpirationHandler(
        cancelling running: Task<Void, Never>,
        gate: CompletionGate,
        complete: @escaping (Bool) -> Void
    ) -> () -> Void {
        {
            running.cancel()
            if gate.claim() { complete(false) }
        }
    }
}

/// Lets exactly one caller through, whichever thread it calls from: the
/// background backup's work and the system's expiration handler race to
/// complete the same BGTask, which must be completed once.
nonisolated final class CompletionGate: Sendable {
    private let claimed = Mutex(false)

    /// True for the first caller only.
    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}

/// Holds a `UIApplication` background task assertion across an async backup
/// so the scene-phase trigger gets time to finish after the app backgrounds.
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
