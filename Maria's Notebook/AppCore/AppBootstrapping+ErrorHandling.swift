import SwiftUI
import CoreData
import OSLog

// MARK: - Error Handling & Core Data Stack Creation

extension AppBootstrapping {

    /// Retrieves or creates the shared Core Data stack.
    /// This manages lazy initialization and error handling.
    @MainActor
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
                fatalError(
                    "CRITICAL: Cannot create any Core Data stack, including fallback. "
                    + "System failure: \(errorDesc)"
                )
            }
        }
    }

    // Legacy getSharedModelContainer() removed — SwiftData migration complete.
}
