import SwiftUI
import CoreData
import OSLog

// MARK: - Error Handling & Core Data Stack Creation

extension AppBootstrapping {

    /// What starts as soon as the notebook's stores are open, whoever opened
    /// them first: the window, or a Siri intent run in the background, which
    /// brings up no scene at all (so the window's bootstrap, which used to
    /// start these, never runs). Both are idempotent; the bootstrap's own
    /// calls stay.
    static func startStoreObservers(_ stack: CoreDataStack) {
        // Classroom records saved from now on go to the share, Siri's included.
        SharedStoreOrphanGuard.shared.start(coreDataStack: stack)
        // An import can finish before any window has configured sync status.
        CloudKitSyncStatusService.watchForFirstDownload(on: stack)
        // So can a failed setup: hold CloudKit's events until `configure`.
        // Not in the test host, whose suites drive the service themselves.
        if !isRunningUnitTests {
            CloudKitSyncStatusService.shared.beginEarlyEventCapture(for: stack)
        }
    }

    /// Builds the shared stack with `create`. A stack that loads is handed to
    /// `didLoad`; a failure lands on the database-error screen with an
    /// in-memory stack behind it, and `didLoad` isn't called.
    ///
    /// The window says "Opening your notebook…" while `create` runs: it
    /// opens the stores off the main thread (`createCoreDataStack`), so the
    /// main thread is free to draw that.
    static func loadSharedStack(
        create: () async throws -> CoreDataStack,
        didLoad: (CoreDataStack) -> Void
    ) async -> CoreDataStack {
        // Signal that we're initializing the container
        AppBootstrapper.shared.setState(.initializingContainer)

        do {
            let logger = Logger.container
            let containerStart = Date()
            logger.info("CoreDataStack: Starting initialization...")

            let stack = try await create()

            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("CoreDataStack: Creation completed in \(elapsed)s")

            // Disable autosave on view context — we use explicit saves via SaveCoordinator
            stack.viewContext.automaticallyMergesChangesFromParent = true

            // Reset state to idle so bootstrap can start
            AppBootstrapper.shared.setState(.idle)

            let totalElapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("CoreDataStack: Total initialization time: \(totalElapsed)s")
            didLoad(stack)
            return stack
        } catch {
            // The screen says this plainly (`DatabaseErrorCoordinator.userMessage`);
            // the raw error goes to the log and the error screen's Details. The
            // error itself is kept, not rewrapped: which kind it is decides
            // what the screen offers.
            let errorDesc = DatabaseErrorCoordinator.technicalDescription(of: error)
            Logger.container.error("CoreDataStack initialization failed: \(errorDesc, privacy: .public)")
            AppBootstrapping.initError = error
            DatabaseErrorCoordinator.shared.setError(error, details: errorDesc)

            // Create an in-memory stack so the app can show the error UI
            do {
                let fallbackStack = try CoreDataStack(enableCloudKit: false, inMemory: true)
                DatabaseInitializationService.markInMemorySession(true)
                UserDefaults.standard.set(errorDesc, forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return fallbackStack
            } catch {
                // Even the in-memory fallback failed (e.g. the compiled model is
                // missing/corrupt). Rather than crash-loop with no UI, launch into
                // the database-error screen backed by an empty, always-constructible
                // stack. The error was already recorded via DatabaseErrorCoordinator.
                Logger.container.fault(
                    "CRITICAL: no Core Data stack could be made; using empty fallback. \(errorDesc, privacy: .public)"
                )
                DatabaseInitializationService.markInMemorySession(true)
                UserDefaults.standard.set(errorDesc, forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return CoreDataStack.makeEmptyFallback()
            }
        }
    }
}
