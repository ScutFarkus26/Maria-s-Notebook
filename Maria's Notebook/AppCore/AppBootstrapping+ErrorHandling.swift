import SwiftUI
import SwiftData
import OSLog

// MARK: - Error Handling & Fallback Container Creation

extension AppBootstrapping {

    /// Retrieves or creates the shared model container.
    /// This property manages lazy initialization and error handling for the container.
    @MainActor
    static func getSharedModelContainer() -> ModelContainer {
        if let existing = _sharedModelContainer {
            return existing
        }

        // Signal that we're initializing the container (this is what takes time)
        AppBootstrapper.shared.setState(.initializingContainer)

        // CRITICAL: If you see a crash at this line (calling createModelContainer()),
        // SwiftData is asserting internally during schema processing.
        //
        // This means there's a problem with the schema definition itself:
        // - Check the crash log for the exact SwiftData assertion message
        // - Look for duplicate entity names in AppSchema.schema
        // - Verify all @Relationship annotations have matching inverses
        // - Check for invalid property types or annotations
        //
        // NOTE: We cannot catch SwiftData's internal assertions - they crash immediately.

        do {
            let containerStart = Date()
            let logger = Logger.app(category: "Container")
            logger.info("ModelContainer: Starting initialization...")

            let container = try AppBootstrapping.createModelContainer()

            logger.info("ModelContainer: Creation completed in \(String(format: "%.3f", Date().timeIntervalSince(containerStart)))s")

            // Configure SQLite to suppress detached signature errors
            AppBootstrapping.configureSQLiteToSuppressDetachedSignatureErrors(for: container)

            // Disable autosave on main context to prevent excessive write contention
            // We rely on explicit saves via SaveCoordinator instead
            container.mainContext.autosaveEnabled = false

            _sharedModelContainer = container

            // Reset state to idle so bootstrap can start
            AppBootstrapper.shared.setState(.idle)

            logger.info("ModelContainer: Total initialization time: \(String(format: "%.3f", Date().timeIntervalSince(containerStart)))s")
            return container
        } catch {
            // This should never be reached if createModelContainer handles all errors properly,
            // but we include it as a safety net
            let errorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
            let unexpectedError = NSError(
                domain: "MariasNotebook",
                code: 6000,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected error during container initialization: \(errorDesc)"]
            )
            AppBootstrapping.initError = unexpectedError
            DatabaseErrorCoordinator.shared.setError(unexpectedError, details: errorDesc)

            // Create an in-memory container with full schema so the app can show the error UI
            // without crashing when code attempts to fetch entities like NonSchoolDay.
            // This is a last resort fallback.
            do {
                let fallbackSchema = AppSchema.schema
                let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                let fallbackContainer = try ModelContainer(for: fallbackSchema, configurations: fallbackConfig)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set(unexpectedError.localizedDescription, forKey: UserDefaultsKeys.lastStoreErrorDescription)
                return fallbackContainer
            } catch {
                // If even this fails, we have no choice but to crash
                // This should never happen in practice
                fatalError("CRITICAL: Cannot create any container, including fallback. System failure: \(errorDesc)")
            }
        }
    }
}
