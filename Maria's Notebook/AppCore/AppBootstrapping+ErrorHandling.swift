import SwiftUI
import CoreData
import OSLog

// MARK: - Error Handling & Core Data Stack Creation

extension AppBootstrapping {

    /// Retrieves or creates the shared Core Data stack.
    /// This manages lazy initialization and error handling.
    static func getSharedCoreDataStack() -> CoreDataStack {
        if let existing = _sharedCoreDataStack {
            return existing
        }

        // Signal that we're initializing the container
        AppBootstrapper.shared.setState(.initializingContainer)

        do {
            let logger = Logger.app(category: "Container")
            let containerStart = Date()
            logger.info("CoreDataStack: Starting initialization...")

            let stack = try AppBootstrapping.createCoreDataStack()

            let elapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("CoreDataStack: Creation completed in \(elapsed)s")

            // Disable autosave on view context — we use explicit saves via SaveCoordinator
            stack.viewContext.automaticallyMergesChangesFromParent = true

            _sharedCoreDataStack = stack

            // Reset state to idle so bootstrap can start
            AppBootstrapper.shared.setState(.idle)

            let totalElapsed = String(format: "%.3f", Date().timeIntervalSince(containerStart))
            logger.info("CoreDataStack: Total initialization time: \(totalElapsed)s")
            return stack
        } catch {
            let errorDesc = (error as NSError).localizedDescription
            let unexpectedError = NSError(
                domain: "MariasNotebook",
                code: 6000,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unexpected error during Core Data stack initialization: \(errorDesc)"
                ]
            )
            AppBootstrapping.initError = unexpectedError
            DatabaseErrorCoordinator.shared.setError(unexpectedError, details: errorDesc)

            // Create an in-memory stack so the app can show the error UI
            do {
                let fallbackStack = try CoreDataStack(enableCloudKit: false, inMemory: true)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set(
                    unexpectedError.localizedDescription,
                    forKey: UserDefaultsKeys.lastStoreErrorDescription
                )
                _sharedCoreDataStack = fallbackStack
                return fallbackStack
            } catch {
                // Even the in-memory fallback failed (e.g. the compiled model is
                // missing/corrupt). Rather than crash-loop with no UI, launch into
                // the database-error screen backed by an empty, always-constructible
                // stack. The error was already recorded via DatabaseErrorCoordinator.
                Logger.app(category: "Container").fault(
                    "CRITICAL: no real Core Data stack could be created; using empty fallback. \(errorDesc, privacy: .public)"
                )
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set(
                    unexpectedError.localizedDescription,
                    forKey: UserDefaultsKeys.lastStoreErrorDescription
                )
                let fallbackStack = CoreDataStack.makeEmptyFallback()
                _sharedCoreDataStack = fallbackStack
                return fallbackStack
            }
        }
    }

    // Legacy getSharedModelContainer() removed — SwiftData migration complete.
}
