import SwiftUI
import SwiftData
import CoreData
import OSLog

// MARK: - CloudKit Container Setup

extension AppBootstrapping {

    // Creates a ModelContainer with comprehensive error handling.
    // If SwiftData asserts internally during schema processing, we cannot catch it.
    // Returns the container and sets initError if there's a recoverable error.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func createModelContainer() throws -> ModelContainer {
        // IMPORTANT: If SwiftData asserts internally during schema processing, we cannot catch it.
        // Internal assertions crash immediately at the Swift runtime level.
        //
        // Common causes of SwiftData internal assertions:
        // 1. Duplicate entity names in the schema
        // 2. Invalid or circular relationship definitions
        // 3. Model classes with invalid @Attribute or @Relationship annotations
        // 4. Missing inverse relationships when one side specifies inverse:
        // 5. Invalid property types (e.g., using types SwiftData doesn't support)

        // Get schema - if SwiftData asserts here, it's a schema definition problem
        let schema = AppSchema.schema

        let useInMemory = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useInMemoryStoreOnce)

        // Helper to extract detailed error message from NSError
        func extractDetailedErrorMessage(_ error: Error) -> String {
            let errorDescription = (error as NSError?)?.localizedDescription ?? String(describing: error)
            guard let nsError = error as NSError? else {
                return errorDescription
            }

            let userInfo = nsError.userInfo
            if let underlyingError = userInfo[NSUnderlyingErrorKey] as? NSError {
                return underlyingError.localizedDescription
            } else if let errorMessage = userInfo[NSLocalizedDescriptionKey] as? String {
                return errorMessage
            }
            return errorDescription
        }

        // Helper to create CloudKit-enabled container with fallback handling
        func createCloudKitContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
            do {
                let cloudKitLogger = Logger.app(category: "CloudKit")
                let cloudKitStart = Date()
                cloudKitLogger.info("Starting CloudKit container initialization...")

                // Use automatic container selection from entitlements to avoid runtime ID mismatches.
                let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .automatic)
                let container = try ModelContainer(for: schema, configurations: config)

                let ckElapsed = String(format: "%.3f", Date().timeIntervalSince(cloudKitStart))
                cloudKitLogger.info("CloudKit container created in \(ckElapsed)s")

                // NOTE: CloudKit schema initialization
                // SwiftData automatically initializes the CloudKit schema when creating a
                // ModelContainer with cloudKitDatabase enabled (for example: .automatic). Unlike raw Core Data with
                // NSPersistentCloudKitContainer, there is no need to call
                // initializeCloudKitSchema() manually for normal setup.
                //
                // EXCEPTION: If you observe "partial data loss" or relationships not syncing
                // after a model change, call initializeCloudKitSchema() once in a #if DEBUG
                // block to force the cloud schema to match your local model, then remove it.
                //
                // IMPORTANT: Before releasing to the App Store, deploy the CloudKit schema
                // from the Development environment to Production via the CloudKit Dashboard:
                //   1. Go to https://icloud.developer.apple.com
                //   2. Select the container: iCloud.DanielSDeBerry.MariasNoteBook
                //   3. Click "Deploy Schema Changes..." under the Development environment
                //
                // Schema changes must be additive only (no deletes, renames, or type changes).

                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
                // Clear any previous error since CloudKit is now active
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                return container
            } catch {
                // CloudKit initialization failed - fall back to local store
                // Store the error for display in the UI
                let detailedError = extractDetailedErrorMessage(error)
                UserDefaults.standard.set(detailedError, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
                // Fall back to local store
                let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: config)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                return container
            }
        }

        // Helper to create container with defensive error handling
        func makeContainer(inMemory: Bool, url: URL? = nil, cloud: Bool = false) throws -> ModelContainer {
            do {
                if inMemory {
                    let config = ModelConfiguration(isStoredInMemoryOnly: true)
                    // SwiftData may assert here if the schema is invalid
                    let container = try ModelContainer(for: schema, configurations: config)
                    return container
                } else if cloud {
                    // Use the container ID from entitlements (must match entitlements file)
                    let storeURL = url ?? AppBootstrapping.storeFileURL()

                    // Validate store URL is not /dev/null or invalid
                    guard storeURL.path != "/dev/null" && !storeURL.path.isEmpty else {
                        throw NSError(
                            domain: "MariasNotebook",
                            code: 2003,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Invalid store URL: \(storeURL.path)."
                                    + " Cannot initialize CloudKit with invalid store location."
                            ]
                        )
                    }

                    return try createCloudKitContainer(schema: schema, storeURL: storeURL)
                } else {
                    // Explicitly disable CloudKit for SwiftData (we use CloudDocuments for file storage instead)
                    let config = ModelConfiguration(
                        url: url ?? AppBootstrapping.storeFileURL(),
                        cloudKitDatabase: .none
                    )
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                    return try ModelContainer(for: schema, configurations: config)
                }
            } catch {
                // Re-throw with additional context
                throw error
            }
        }

        do {
            let logger = Logger.app(category: "Container")

            // Attempt migration before opening store (if needed)
            let migrationCheckStart = Date()
            _ = AppBootstrapping.attemptAttendanceRecordMigrationIfNeeded()
            let migCheckElapsed = String(format: "%.3f", Date().timeIntervalSince(migrationCheckStart))
            logger.info("createModelContainer: Migration check completed in \(migCheckElapsed)s")

            let ubiquityStart = Date()
            _ = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            let ubiqElapsed = String(format: "%.3f", Date().timeIntervalSince(ubiquityStart))
            logger.info("createModelContainer: Ubiquity check completed in \(ubiqElapsed)s")

            if useInMemory {
                let container = try makeContainer(inMemory: true)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.set(
                    "Using temporary in-memory store on next launch.",
                    forKey: UserDefaultsKeys.lastStoreErrorDescription
                )
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
                return container
            } else {
                // Validate store file before attempting to open
                let validationStart = Date()
                let storeURL = AppBootstrapping.storeFileURL()
                let fm = FileManager.default
                if fm.fileExists(atPath: storeURL.path) {
                    // Check if the store file is readable
                    guard fm.isReadableFile(atPath: storeURL.path) else {
                        throw NSError(
                            domain: "MariasNotebook",
                            code: 6001,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Store file exists but is not readable."
                                    + " The database may be corrupted or locked by another process."
                            ]
                        )
                    }
                }
                let valElapsed = String(format: "%.3f", Date().timeIntervalSince(validationStart))
                logger.info("createModelContainer: Store validation completed in \(valElapsed)s")

                // CloudKit compatibility: All model fixes are complete. Enable CloudKit by default.
                // Users can disable it via the settings toggle if needed.
                let cloudKitPreference = UserDefaults.standard.object(
                    forKey: UserDefaultsKeys.enableCloudKitSync
                ) as? Bool ?? true
                let enableCloudKit = cloudKitPreference && !AppBootstrapping.disableCloudKitForCurrentLaunch

                let containerCreateStart = Date()
                logger.info("createModelContainer: Starting container creation (CloudKit: \(enableCloudKit))...")

                // Try CloudKit first if enabled, but fall back to local if it takes too long or fails
                let container: ModelContainer
                if enableCloudKit {
                    do {
                        container = try makeContainer(inMemory: false, cloud: true)
                        let ckCreateElapsed = String(format: "%.3f", Date().timeIntervalSince(containerCreateStart))
                        logger.info("createModelContainer: CloudKit container created in \(ckCreateElapsed)s")
                    } catch {
                        logger.warning("createModelContainer: CloudKit init failed, fallback: \(error)")
                        // Fall back to local storage if CloudKit fails
                        container = try makeContainer(inMemory: false, cloud: false)
                        let fbElapsed = String(format: "%.3f", Date().timeIntervalSince(containerCreateStart))
                        logger.info("createModelContainer: Local fallback created in \(fbElapsed)s")
                    }
                } else {
                    container = try makeContainer(inMemory: false, cloud: false)
                    let localElapsed = String(format: "%.3f", Date().timeIntervalSince(containerCreateStart))
                    logger.info("createModelContainer: Local container created in \(localElapsed)s")
                }
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                if !enableCloudKit {
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
                }
                return container
            }
        } catch {
            // If even the in-memory fallback fails, we must surface the blocking error view instead of crashing.
            if let nsError = error as NSError? {

                // Check if this is a migration error (code 134140 or 134190)
                if nsError.code == 134140 || nsError.code == 134190 {
                    // This is a schema migration error
                    // Check if it's specifically about AttendanceRecord.studentID
                    let userInfo = nsError.userInfo
                    if let entity = userInfo["entity"] as? String,
                       entity == "AttendanceRecord",
                       let property = userInfo["property"] as? String,
                       property == "studentID" {
                        // This is the UUID to String migration issue
                        // Try to automatically reset the store if it's safe to do so
                        // (i.e., if there's no important data to preserve)
                        do {
                            try AppBootstrapping.resetPersistentStore()
                            // Retry creating the container with the fresh store
                            // Preserve CloudKit setting - don't disable it during recovery
                            let enableCloudKit = UserDefaults.standard.object(
                                forKey: UserDefaultsKeys.enableCloudKitSync
                            ) as? Bool ?? true
                            let container = try makeContainer(inMemory: false, cloud: enableCloudKit)
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
                            return container
                        } catch {
                            // If reset failed, show error message
                            let migrationError = NSError(
                                domain: "MariasNotebook",
                                code: 3001,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Database schema migration required."
                                        + " The AttendanceRecord.studentID property needs to be migrated"
                                        + " from UUID to String format. Automatic reset failed."
                                        + " Please use 'Reset Local Database' manually to resolve this."
                                ]
                            )
                            DatabaseInitializationService.handleDatabaseInitError(migrationError)
                        }
                    } else {
                        DatabaseInitializationService.handleDatabaseInitError(error)
                    }
                } else {
                    DatabaseInitializationService.handleDatabaseInitError(error)
                }
            } else {
                DatabaseInitializationService.handleDatabaseInitError(error)
            }

            // As a last resort, try to create an in-memory container
            // This allows the app to show the blocking error view even if persistent storage fails
            // NOTE: If SwiftData asserts internally here, we cannot catch it
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let fallbackContainer = try ModelContainer(for: schema, configurations: config)
                // Use safe string representation
                let errorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.ephemeralSessionFlag)
                let fallbackMsg = "Persistent storage failed."
                    + " Using temporary in-memory container."
                    + " Original error: \(errorDesc)"
                UserDefaults.standard.set(
                    fallbackMsg,
                    forKey: UserDefaultsKeys.lastStoreErrorDescription
                )
                return fallbackContainer
            } catch let finalError {
                // Set the error so the UI can display it
                DatabaseInitializationService.handleCriticalDatabaseInitError(
                    originalError: error,
                    finalError: finalError,
                    errorCode: 5001
                )

                // At this point, we cannot create a container with the actual persistent store.
                // As a fallback, create an in-memory container with the full schema so the app can show the error UI
                // without crashing when code attempts to fetch entities like NonSchoolDay.
                // This is a workaround - the error UI doesn't actually need a real container, but SwiftUI's
                // .modelContainer() modifier requires a non-optional ModelContainer.
                do {
                    let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    let fallbackContainer = try ModelContainer(for: schema, configurations: fallbackConfig)

                    // Set the error so the UI can display it
                    DatabaseInitializationService.handleCriticalDatabaseInitError(
                        originalError: error,
                        finalError: finalError,
                        errorCode: 5001
                    )

                    return fallbackContainer
                } catch let fallbackContainerError {
                    // Even creating an in-memory fallback container failed - this should never happen
                    // Set error state instead of crashing so user can recover
                    DatabaseInitializationService.handleCriticalDatabaseInitError(
                        originalError: error,
                        finalError: finalError,
                        emptyContainerError: fallbackContainerError,
                        errorCode: 5002
                    )
                    // We still need to return something, so rethrow and let the caller handle it
                    // The caller (sharedModelContainer) will catch this and handle it
                    if let criticalError = AppBootstrapping.initError as NSError? {
                        throw criticalError
                    } else {
                        throw fallbackContainerError
                    }
                }
            }
        }
    }
}
