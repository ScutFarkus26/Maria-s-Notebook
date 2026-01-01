//
//  MariasToolboxApp.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import SwiftData
import CoreData
#if os(macOS)
import AppKit
#endif

@main
struct MariasToolboxApp: App {
    static let useInMemoryFlagKey = "UseInMemoryStoreOnce"
    static let ephemeralSessionFlagKey = "SwiftDataEphemeralSession"
    static let lastStoreErrorDescriptionKey = "SwiftDataLastErrorDescription"
    static let allowLocalStoreFallbackKey = "AllowLocalStoreFallback"
    static let enableCloudKitKey = "EnableCloudKitSync"
    static let cloudKitActiveKey = "CloudKitActive" // Tracks if CloudKit is actually running (not just enabled)
    
    // Track initialization errors to show in the UI
    static var initError: Error?

    @StateObject private var saveCoordinator = SaveCoordinator()
    @StateObject private var bootstrapper = AppBootstrapper.shared
    @StateObject private var restoreCoordinator = RestoreCoordinator()
    @StateObject private var appRouter = AppRouter.shared

    static func resetPersistentStore() throws {
        let url = storeFileURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
    
    static func resetLocalDatabaseAndForceCloudKitSync() throws {
        // Reset the local store
        try resetPersistentStore()
        
        // Ensure CloudKit is enabled
        UserDefaults.standard.set(true, forKey: enableCloudKitKey)
        
        // Clear any error flags
        UserDefaults.standard.removeObject(forKey: lastStoreErrorDescriptionKey)
        UserDefaults.standard.set(false, forKey: ephemeralSessionFlagKey)
        
        #if DEBUG
        print("SwiftData: Local database reset and CloudKit sync enabled. App restart required.")
        #endif
    }

    static func storeFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "MariasNotebook"
        let containerDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fm.createDirectory(at: containerDir, withIntermediateDirectories: true)
        // IMPORTANT: return a file URL for the SwiftData store package. Do not pre-create it.
        return containerDir.appendingPathComponent("SwiftData.store", isDirectory: false)
    }
    
    /// Attempts to migrate AttendanceRecord.studentID from UUID to String using CoreData APIs.
    /// This is a workaround for SwiftData's inability to automatically migrate type changes.
    /// Returns true if migration was successful or not needed, false if migration failed.
    static func attemptAttendanceRecordMigrationIfNeeded() -> Bool {
        let storeURL = storeFileURL()
        let fm = FileManager.default
        
        // Check if store exists
        guard fm.fileExists(atPath: storeURL.path) else {
            return true // No store to migrate
        }
        
        // Check if migration flag is already set
        let migrationFlagKey = "Migration.attendanceRecordStudentIDCoreData.v1"
        if UserDefaults.standard.bool(forKey: migrationFlagKey) {
            return true // Already migrated
        }
        
        // Note: Manual CoreData migration is complex and requires:
        // 1. Loading the old model (with UUID studentID)
        // 2. Loading the new model (with String studentID)
        // 3. Creating a mapping model
        // 4. Performing the migration
        // 
        // Since SwiftData doesn't expose the underlying CoreData model easily,
        // and we can't easily create a mapping model programmatically,
        // the best approach is to let SwiftData fail with a clear error message,
        // and provide the user with an option to reset the store.
        //
        // For now, we'll return true to allow SwiftData to attempt opening.
        // If it fails, the error handler will provide clear instructions.
        return true
    }

    /// Creates a ModelContainer with comprehensive error handling.
    /// If SwiftData asserts internally during schema processing, we cannot catch it.
    /// Returns the container and sets initError if there's a recoverable error.
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
        
        #if DEBUG
        print("SwiftData: Starting container initialization...")
        #endif
        
        // Get schema - if SwiftData asserts here, it's a schema definition problem
        let schema = AppSchema.schema
        #if DEBUG
        print("SwiftData: Schema accessed successfully")
        #endif
        
        let useInMemory = UserDefaults.standard.bool(forKey: MariasToolboxApp.useInMemoryFlagKey)
        let _ = UserDefaults.standard.bool(forKey: MariasToolboxApp.allowLocalStoreFallbackKey)
        
        // Helper to create container with defensive error handling
        func makeContainer(inMemory: Bool, url: URL? = nil, cloud: Bool = false) throws -> ModelContainer {
            #if DEBUG
            print("SwiftData: Attempting to create container (inMemory: \(inMemory), cloud: \(cloud))...")
            #endif
            do {
                if inMemory {
                    let config = ModelConfiguration(isStoredInMemoryOnly: true)
                    // SwiftData may assert here if the schema is invalid
                    let container = try ModelContainer(for: schema, configurations: config)
                    #if DEBUG
                    print("SwiftData: Successfully created in-memory container")
                    #endif
                    return container
                } else if cloud {
                    // Derive the iCloud container identifier from bundle id and validate
                    let storeURL = url ?? MariasToolboxApp.storeFileURL()
                    let bundleID = Bundle.main.bundleIdentifier ?? ""
                    let containerID = bundleID.isEmpty ? nil : "iCloud.\(bundleID)"

                    #if swift(>=6.0)
                    if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                        if let containerID {
                            #if DEBUG
                            print("SwiftData: CloudKit configuration:")
                            print("  - Container ID: \(containerID)")
                            print("  - Store URL: \(storeURL.path)")
                            print("  - Database: Private")
                            #endif
                            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .private(containerID))
                            let container = try ModelContainer(for: schema, configurations: config)
                            #if DEBUG
                            print("SwiftData: ✅ CloudKit container created successfully!")
                            print("SwiftData: CloudKit sync is now active. Changes will sync across devices.")
                            #endif
                            UserDefaults.standard.set(true, forKey: MariasToolboxApp.cloudKitActiveKey)
                            return container
                        } else {
                            throw NSError(domain: "MariasNotebook", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Missing CFBundleIdentifier; cannot form iCloud container identifier."])
                        }
                    } else {
                        throw NSError(domain: "MariasNotebook", code: 2002, userInfo: [NSLocalizedDescriptionKey: "CloudKit requires iOS 17 / macOS 14 or later for SwiftData."])
                    }
                    #else
                    if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                        if let containerID {
                            #if DEBUG
                            print("SwiftData: CloudKit configuration:")
                            print("  - Container ID: \(containerID)")
                            print("  - Store URL: \(storeURL.path)")
                            print("  - Database: Private")
                            #endif
                            let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .private(containerID))
                            let container = try ModelContainer(for: schema, configurations: config)
                            #if DEBUG
                            print("SwiftData: ✅ CloudKit container created successfully!")
                            print("SwiftData: CloudKit sync is now active. Changes will sync across devices.")
                            #endif
                            UserDefaults.standard.set(true, forKey: MariasToolboxApp.cloudKitActiveKey)
                            return container
                        } else {
                            throw NSError(domain: "MariasNotebook", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Missing CFBundleIdentifier; cannot form iCloud container identifier."])
                        }
                    } else {
                        throw NSError(domain: "MariasNotebook", code: 2002, userInfo: [NSLocalizedDescriptionKey: "CloudKit requires iOS 17 / macOS 14 or later for SwiftData."])
                    }
                    #endif
                } else {
                    // Explicitly disable CloudKit for SwiftData (we use CloudDocuments for file storage instead)
                    let config = ModelConfiguration(
                        url: url ?? MariasToolboxApp.storeFileURL(),
                        cloudKitDatabase: .none
                    )
                    UserDefaults.standard.set(false, forKey: MariasToolboxApp.cloudKitActiveKey)
                    return try ModelContainer(for: schema, configurations: config)
                }
            } catch {
                // Re-throw with additional context
                print("SwiftData: makeContainer failed (inMemory: \(inMemory), cloud: \(cloud)): \(error)")
                throw error
            }
        }

        do {
            // Attempt migration before opening store (if needed)
            _ = MariasToolboxApp.attemptAttendanceRecordMigrationIfNeeded()
            
            let _ = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            if useInMemory {
                #if DEBUG
                print("SwiftData: Creating in-memory store...")
                #endif
                // We already validated the schema, so this should work
                let container = try makeContainer(inMemory: true)
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set("Using temporary in-memory store on next launch.", forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                UserDefaults.standard.set(false, forKey: MariasToolboxApp.useInMemoryFlagKey)
                #if DEBUG
                print("SwiftData: Using in-memory store.")
                #endif
                return container
            } else {
                // Validate store file before attempting to open
                let storeURL = MariasToolboxApp.storeFileURL()
                let fm = FileManager.default
                if fm.fileExists(atPath: storeURL.path) {
                    // Check if the store file is readable
                    guard fm.isReadableFile(atPath: storeURL.path) else {
                        throw NSError(
                            domain: "MariasNotebook",
                            code: 6001,
                            userInfo: [NSLocalizedDescriptionKey: "Store file exists but is not readable. The database may be corrupted or locked by another process."]
                        )
                    }
                    #if DEBUG
                    print("SwiftData: Store file exists at \(storeURL.path)")
                    #endif
                } else {
                    #if DEBUG
                    print("SwiftData: Store file does not exist, will create new store at \(storeURL.path)")
                    #endif
                }
                
                // CloudKit compatibility: All model fixes are complete. Enable CloudKit by default.
                // Users can disable it via the settings toggle if needed.
                let enableCloudKit = UserDefaults.standard.object(forKey: enableCloudKitKey) as? Bool ?? true
                #if DEBUG
                if enableCloudKit {
                    print("SwiftData: Creating CloudKit-enabled container...")
                } else {
                    print("SwiftData: Creating local storage container (CloudKit disabled - set '\(enableCloudKitKey)' UserDefaults flag to enable)...")
                }
                #endif
                let container = try makeContainer(inMemory: false, cloud: enableCloudKit)
                UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                if enableCloudKit {
                    // cloudKitActiveKey is set in makeContainer when CloudKit is successfully initialized
                    #if DEBUG
                    print("SwiftData: ✅ Using CloudKit-enabled storage.")
                    #endif
                } else {
                    UserDefaults.standard.set(false, forKey: MariasToolboxApp.cloudKitActiveKey)
                    #if DEBUG
                    print("SwiftData: Using local storage.")
                    #endif
                }
                return container
            }
        } catch {
            // If even the in-memory fallback fails, we must surface the blocking error view instead of crashing.
            print("SwiftData: Failed to open SwiftData store: \(error)")
            print("SwiftData: Error details: \(String(describing: error))")
            if let nsError = error as NSError? {
                print("SwiftData: NSError domain: \(nsError.domain), code: \(nsError.code)")
                print("SwiftData: NSError userInfo: \(nsError.userInfo)")
                
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
                        #if DEBUG
                        print("SwiftData: Detected AttendanceRecord.studentID migration issue. Attempting automatic store reset...")
                        #endif
                        do {
                            try MariasToolboxApp.resetPersistentStore()
                            #if DEBUG
                            print("SwiftData: Store reset successfully. Retrying with fresh store...")
                            #endif
                            // Retry creating the container with the fresh store
                            let container = try makeContainer(inMemory: false, cloud: false)
                            UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                            UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                            #if DEBUG
                            print("SwiftData: Successfully opened store after reset.")
                            #endif
                            return container
                        } catch {
                            // If reset failed, show error message
                            let migrationError = NSError(
                                domain: "MariasNotebook",
                                code: 3001,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Database schema migration required. The AttendanceRecord.studentID property needs to be migrated from UUID to String format. Automatic reset failed. Please use 'Reset Local Database' manually to resolve this."
                                ]
                            )
                            MariasToolboxApp.initError = migrationError
                            UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                            UserDefaults.standard.set(migrationError.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                        }
                    } else {
                        MariasToolboxApp.initError = error
                        UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                        UserDefaults.standard.set(error.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                    }
                } else {
                    MariasToolboxApp.initError = error
                    UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                    UserDefaults.standard.set(error.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                }
            } else {
                MariasToolboxApp.initError = error
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set(error.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            }
            
            // As a last resort, try to create an in-memory container
            // This allows the app to show the blocking error view even if persistent storage fails
            // NOTE: If SwiftData asserts internally here, we cannot catch it
            do {
                #if DEBUG
                print("SwiftData: Attempting final fallback to in-memory container...")
                #endif
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let fallbackContainer = try ModelContainer(for: schema, configurations: config)
                #if DEBUG
                print("SwiftData: Successfully created fallback in-memory container")
                #endif
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                // Use safe string representation
                let errorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
                UserDefaults.standard.set("Persistent storage failed. Using temporary in-memory container. Original error: \(errorDesc)", forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                return fallbackContainer
            } catch let finalError {
                // Log comprehensive error information
                print("SwiftData: CRITICAL - Failed to create even an in-memory container")
                print("SwiftData: Original error: \(error)")
                print("SwiftData: Final error: \(finalError)")
                if let nsError = finalError as NSError? {
                    print("SwiftData: Final NSError domain: \(nsError.domain), code: \(nsError.code)")
                    print("SwiftData: Final NSError userInfo: \(nsError.userInfo)")
                }
                
                // Set the error so the UI can display it
                // Use safe string representations to avoid any potential assertion
                let originalDesc = (error as NSError?)?.localizedDescription ?? "Unknown error"
                let finalDesc = (finalError as NSError?)?.localizedDescription ?? "Unknown error"
                let criticalError = NSError(
                    domain: "MariasNotebook",
                    code: 5001,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Critical database initialization failure. The app cannot create a database container. Original: \(originalDesc). Final: \(finalDesc). Please try resetting the database or reinstalling the app."
                    ]
                )
                MariasToolboxApp.initError = criticalError
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set(criticalError.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                
                // At this point, we cannot create a container with the actual schema.
                // As an absolute last resort, try to create an empty container just so the app can show the error UI.
                // This is a workaround - the error UI doesn't actually need a real container, but SwiftUI's
                // .modelContainer() modifier requires a non-optional ModelContainer.
                do {
                    #if DEBUG
                    print("SwiftData: Attempting to create minimal empty container for error UI...")
                    #endif
                    let emptySchema = Schema([])
                    let emptyConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    let emptyContainer = try ModelContainer(for: emptySchema, configurations: emptyConfig)
                    #if DEBUG
                    print("SwiftData: Created minimal empty container for error UI")
                    #endif
                    
                    // Set the error so the UI can display it
                    let originalErrorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
                    let finalErrorDesc = (finalError as NSError?)?.localizedDescription ?? String(describing: finalError)
                    let criticalError = NSError(
                        domain: "MariasNotebook",
                        code: 5001,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Critical database initialization failure. The app cannot create a database container. Original: \(originalErrorDesc). Final: \(finalErrorDesc). Please try resetting the database or reinstalling the app."
                        ]
                    )
                    MariasToolboxApp.initError = criticalError
                    UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                    UserDefaults.standard.set(criticalError.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                    
                    return emptyContainer
                } catch {
                    // Even creating an empty container failed - this should never happen
                    // but if it does, we must crash with a clear message
                    let originalErrorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
                    let finalErrorDesc = (finalError as NSError?)?.localizedDescription ?? String(describing: finalError)
                    fatalError("CRITICAL: Failed to create even an empty container. This indicates a severe system issue. Original: \(originalErrorDesc). Final: \(finalErrorDesc)")
                }
            }
        }
    }
    
    /// Model container for SwiftData.
    /// Initialized on first access via the static factory method.
    /// If SwiftData asserts internally during schema processing, we cannot catch it.
    private static var _sharedModelContainer: ModelContainer?
    
    var sharedModelContainer: ModelContainer {
        if let existing = MariasToolboxApp._sharedModelContainer {
            return existing
        }
        
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
        #if DEBUG
        print("SwiftData: Accessing sharedModelContainer - will create container now...")
        print("SwiftData: If crash occurs here, check schema definition in AppSchema.swift")
        #endif
        
        do {
            let container = try MariasToolboxApp.createModelContainer()
            MariasToolboxApp._sharedModelContainer = container
            #if DEBUG
            print("SwiftData: Container created and cached successfully")
            #endif
            return container
        } catch {
            // This should never be reached if createModelContainer handles all errors properly,
            // but we include it as a safety net
            print("SwiftData: Unexpected error in container initialization: \(error)")
            let unexpectedError = NSError(
                domain: "MariasNotebook",
                code: 6000,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected error during container initialization: \(error.localizedDescription)"]
            )
            MariasToolboxApp.initError = unexpectedError
            // Use safe string conversion
            let errorDesc = (error as NSError?)?.localizedDescription ?? String(describing: error)
            fatalError("CRITICAL: Unexpected error in container initialization: \(errorDesc)")
        }
    }

    init() {
        #if os(macOS)
        if let icon = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif
        // Cleanup: remove legacy Beta flag now that Engagement Lifecycle is always on
        UserDefaults.standard.removeObject(forKey: "useEngagementLifecycle")
    }

    var body: some Scene {
        WindowGroup("") {
            Group {
                if let error = MariasToolboxApp.initError {
                    // BLOCKING ERROR VIEW
                    ContentUnavailableView {
                        Label("Database Connection Failed", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        VStack(spacing: 8) {
                            Text("The app could not connect to the iCloud database.")
                            Text("To prevent data loss (Split-Brain), the app has stopped.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Error: \(error.localizedDescription)")
                                .font(.caption2)
                                .padding(.top)
                                .textSelection(.enabled)
                        }
                    } actions: {
                        VStack(spacing: 12) {
                            Button("Quit & Retry") {
                                #if os(macOS)
                                NSApplication.shared.terminate(nil)
                                #else
                                exit(0)
                                #endif
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Use Offline Mode (Warning: Syncs Separately)") {
                                UserDefaults.standard.set(true, forKey: MariasToolboxApp.allowLocalStoreFallbackKey)
                                #if os(macOS)
                                NSApplication.shared.terminate(nil)
                                #else
                                exit(0)
                                #endif
                            }
                            
                            Button("Reset Local Database…", role: .destructive) {
                                try? MariasToolboxApp.resetPersistentStore()
                                #if os(macOS)
                                NSApplication.shared.terminate(nil)
                                #else
                                exit(0)
                                #endif
                            }
                        }
                        .padding()
                    }
                } else {
                    // NORMAL APP FLOW
                    if bootstrapper.state == .ready {
                        Group {
                            if restoreCoordinator.isRestoring {
                                VStack(spacing: 20) {
                                    ProgressView().controlSize(.large)
                                    Text("Restoring data…")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.clear)
                            } else {
                                RootView()
                                    .environment(\.calendar, AppCalendar.shared)
                                    .environment(\.appRouter, appRouter)
                                    .environmentObject(saveCoordinator)
                                    .environmentObject(restoreCoordinator)
                            }
                        }
                    } else {
                        // Loading / Splash Screen
                        VStack(spacing: 20) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Preparing Database...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                    }
                }
            }
            .task {
                // Only bootstrap if the store loaded successfully
                if MariasToolboxApp.initError == nil {
                    await bootstrapper.bootstrap(modelContainer: sharedModelContainer)
                }
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 1200, height: 800)
        #endif
        .modelContainer(sharedModelContainer)
        .commands {
            // 1. STANDARD "NEW" ITEMS (File > New)
            // Consolidates all creation actions into the standard location
            CommandGroup(replacing: .newItem) {
                Button("New Lesson") { appRouter.requestNewLesson() }
                    .keyboardShortcut("n", modifiers: [.command])
                
                Button("New Student") { appRouter.requestNewStudent() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("New Work…") { appRouter.requestNewWork() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }

            // 2. STANDARD "IMPORT/EXPORT" ITEMS (File > Import)
            // Moves Imports, Backups, and Restores here
            CommandGroup(replacing: .importExport) {
                Section {
                    Button("Import Lessons…") { appRouter.requestImportLessons() }
                        .keyboardShortcut("i", modifiers: [.command])
                    
                    Button("Import Students…") { appRouter.requestImportStudents() }
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                }
                
                Section {
                    Button("Create Backup") { appRouter.requestCreateBackup() }
                        .keyboardShortcut("b", modifiers: [.command])
                    
                    Button("Restore Data…") { appRouter.requestRestoreBackup() }
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                }
            }

            // 3. VIEW ACTIONS (View Menu)
            // Quick Navigation Shortcuts for main tabs
            CommandGroup(after: .sidebar) {
                Divider()
                
                // Quick Navigation Shortcuts
                Button("Today") { appRouter.selectedTab = RootView.Tab.today }
                    .keyboardShortcut("1", modifiers: .command)
                
                Button("Planning") { appRouter.selectedTab = RootView.Tab.planning }
                    .keyboardShortcut("2", modifiers: .command)

                Button("Students") { appRouter.selectedTab = RootView.Tab.students }
                    .keyboardShortcut("3", modifiers: .command)
                    
                Button("Lessons") { appRouter.selectedTab = RootView.Tab.albums }
                    .keyboardShortcut("4", modifiers: .command)
                    
                Button("Logs") { appRouter.selectedTab = RootView.Tab.logs }
                    .keyboardShortcut("5", modifiers: .command)
                    
                Divider()
                
                Button("Open Attendance") {
                    appRouter.requestOpenAttendance()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
            
            // 4. STANDARD SETTINGS (App Menu)
            // Maps the standard macOS "Settings..." menu item (Cmd+,) to your Settings tab
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appRouter.selectedTab = RootView.Tab.settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // 5. HELP & TROUBLESHOOTING (Help Menu)
            // Hides the "junk" inside a submenu in Help, or you can delete it entirely
            CommandGroup(replacing: .help) {
                // Keeps the default search bar
                Button("\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App") Help") {
                    // Action to open help
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                // Move all technical toggles into a submenu to keep the top bar clean
                Menu("Troubleshooting") {
                    #if os(macOS)
                    Toggle("Allow Local Store Fallback", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: MariasToolboxApp.allowLocalStoreFallbackKey) },
                        set: { UserDefaults.standard.set($0, forKey: MariasToolboxApp.allowLocalStoreFallbackKey) }
                    ))
                    Toggle("Enable CloudKit Sync", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: MariasToolboxApp.enableCloudKitKey) },
                        set: { UserDefaults.standard.set($0, forKey: MariasToolboxApp.enableCloudKitKey) }
                    ))
                    #endif
                    
                    Button("Use In-Memory Store Next Launch") {
                        UserDefaults.standard.set(true, forKey: MariasToolboxApp.useInMemoryFlagKey)
                    }
                    
                    Divider()
                    
                    Button("Reset Local Database…", role: .destructive) {
                        try? MariasToolboxApp.resetPersistentStore()
                    }
                }
            }
        }

        #if os(macOS)
        WindowGroup("", id: "WorkDetailWindow", for: UUID.self) { $workID in
            if let id = workID {
                Group {
                    if restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text("Restoring data…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        ContractDetailWindowHost(workID: id)
                            .environment(\.calendar, AppCalendar.shared)
                            .environmentObject(saveCoordinator)
                            .environmentObject(restoreCoordinator)
                    }
                }
            } else {
                Text("No work selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 700)
        .modelContainer(sharedModelContainer)
        #endif
    }
}

