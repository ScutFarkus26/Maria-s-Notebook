//
//  MariasToolboxApp.swift
//  Maria's Toolbox
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct MariasToolboxApp: App {
    static let useInMemoryFlagKey = "UseInMemoryStoreOnce"
    static let ephemeralSessionFlagKey = "SwiftDataEphemeralSession"
    static let lastStoreErrorDescriptionKey = "SwiftDataLastErrorDescription"
    static let allowLocalStoreFallbackKey = "AllowLocalStoreFallback"

    @StateObject private var saveCoordinator = SaveCoordinator()

    /// Remove the local persistent store directory to allow the app to recreate a fresh store on next launch.
    /// NOTE: When using a CloudKit-backed SwiftData store, the system manages the store location and this path
    /// may not be used. To fully reset CloudKit development data, use CloudKit Dashboard (Development DB) and
    /// then reinstall/relaunch the app.
    static func resetPersistentStore() throws {
        let url = storeDirectoryURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Directory where the SwiftData store will be placed.
    /// Using an explicit location makes it possible to reset/repair the store safely.
    static func storeDirectoryURL() -> URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "MariasToolbox"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("SwiftDataStore", isDirectory: true)
        // Ensure the parent directory exists; SwiftData will create the terminal directory as needed.
        try? fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        return dir
    }

    /*
     CloudKit Sync Notes (SwiftData)
     --------------------------------
     - This app uses SwiftData with a CloudKit-backed ModelContainer so your data syncs
       between macOS and iPadOS (including iPad Simulator) via the same CloudKit container.
     - To test syncing:
       • Sign into the SAME iCloud Apple ID on your Mac (System Settings → Apple ID), your physical iPad (Settings → Apple ID), and inside the iPad Simulator (Settings app → sign in).
       • Run the SAME build/version of the app on macOS, iPad, and the iPad Simulator.
       • Make changes on one device; they will propagate to the others. CloudKit may take a short time to deliver changes (a few seconds to a couple of minutes), especially after first launch.
     - Free Apple developer account limitations:
       • Sync uses the CloudKit DEVELOPMENT environment only. Your data and schema live only in development.
       • Apps installed on a device with a free profile expire after ~7 days and must be reinstalled.
       • If you need to reset all development data, use CloudKit Dashboard (Development DB) to delete records/types, then reinstall and relaunch the app so SwiftData can re-create the schema.
     - Troubleshooting:
       • If you toggle the in-memory store (Troubleshooting menu), syncing is disabled for that launch.
       • Ensure both the macOS and iPadOS targets use the SAME Team, Bundle ID family, and CloudKit container.
    */
    var sharedModelContainer: ModelContainer = {
        let schema = AppSchema.schema
        let useInMemory = UserDefaults.standard.bool(forKey: MariasToolboxApp.useInMemoryFlagKey)
        do {
            if useInMemory {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: config)
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set("Using in-memory store by user toggle.", forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                UserDefaults.standard.set(false, forKey: MariasToolboxApp.useInMemoryFlagKey)
                print("SwiftData: Using in-memory store for this launch (toggle enabled).")
                return container
            } else {
                // Primary: Open a CloudKit-backed store using the explicit private container.
                let schema = AppSchema.schema
                do {
                    let cloudConfig = ModelConfiguration(
                        schema: schema,
                        cloudKitDatabase: .private("iCloud.mariastoolbox")
                    )
                    let cloudContainer = try ModelContainer(for: schema, configurations: cloudConfig)
                    UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                    UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                    return cloudContainer
                } catch {
                    let ns = error as NSError
                    // Log full error and persist a readable message
                    print("SwiftData: CloudKit store failed to open (explicit). Error:", ns)
                    print("userInfo:", ns.userInfo)
                    var message = "\(ns.domain) code=\(ns.code): \(ns.localizedDescription)"
                    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                        message += " | underlying: \(underlying.domain) code=\(underlying.code): \(underlying.localizedDescription)"
                    }
                    UserDefaults.standard.set(message, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)

                    // Always attempt local persistent fallback if CloudKit open fails.
                    // This prevents a hard crash on launch and lets the app run offline.
                    do {
                        let localConfig = ModelConfiguration(url: MariasToolboxApp.storeDirectoryURL())
                        let localContainer = try ModelContainer(for: schema, configurations: localConfig)
                        UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                        print("SwiftData: Falling back to local persistent store at", MariasToolboxApp.storeDirectoryURL().path)
                        return localContainer
                    } catch {
                        #if DEBUG
                        assertionFailure("SwiftData CloudKit container open failed and local fallback also failed: \(message) | local error: \(error)")
                        #endif
                        // If local fallback also fails, rethrow to outer handler.
                        throw error
                    }
                }
            }
        } catch {
            let ns = error as NSError
            print("SwiftData (CloudKit) container error:", error)
            print("userInfo:", ns.userInfo)
            var message = "\(ns.domain) code=\(ns.code): \(ns.localizedDescription)"
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                message += " | underlying: \(underlying.domain) code=\(underlying.code): \(underlying.localizedDescription)"
            }
            UserDefaults.standard.set(message, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
            #if DEBUG
            assertionFailure("SwiftData persistent store failed to open: \(message)")
            #endif
            fatalError("Failed to open persistent SwiftData store: \(message)")
        }
    }()

    init() {
        #if os(macOS)
        if let icon = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("") {
            RootView()
                .environment(\.calendar, AppCalendar.shared)
                .environmentObject(saveCoordinator)
                .onAppear {
                    DataMigrations.repairScheduledForDayIfNeeded(using: sharedModelContainer.mainContext, calendar: AppCalendar.shared)
                    NotificationCenter.default.post(name: .PlanningInboxNeedsRefresh, object: nil)
                    AppCalendar.adopt(timeZoneFrom: Calendar.current)
                    MigrationRunner.runIfNeeded(context: sharedModelContainer.mainContext)
                    DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: sharedModelContainer.mainContext)
                    DataMigrations.normalizeWorkDatesToDateOnlyIfNeeded(using: sharedModelContainer.mainContext)
                    DataMigrations.backfillParticipantsAndDeleteEmptyWorksIfNeeded(using: sharedModelContainer.mainContext)
                    DataMigrations.backfillEmptyWorkTitlesIfNeeded(using: sharedModelContainer.mainContext)

                    // Run legacy scoped notes migration once, non-blocking
                    Task {
                        let context = ModelContext(sharedModelContainer)
                        LegacyNotesMigration.runIfNeeded(modelContext: context)
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
            CommandMenu("Lessons") {
                Button("New Lesson") { NotificationCenter.default.post(name: Notification.Name("NewLessonRequested"), object: nil) }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Import Lessons…") { NotificationCenter.default.post(name: Notification.Name("ImportLessonsRequested"), object: nil) }
                    .keyboardShortcut("i", modifiers: [.command])
            }
            CommandMenu("Students") {
                Button("New Student") { NotificationCenter.default.post(name: Notification.Name("NewStudentRequested"), object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Import Students…") { NotificationCenter.default.post(name: Notification.Name("ImportStudentsRequested"), object: nil) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("Backup") {
                Button("Create Backup") { NotificationCenter.default.post(name: Notification.Name("CreateBackupRequested"), object: nil) }
                    .keyboardShortcut("b", modifiers: [.command])
                Button("Restore…") { NotificationCenter.default.post(name: Notification.Name("RestoreBackupRequested"), object: nil) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandMenu("Work") {
                Button("New Work…") { NotificationCenter.default.post(name: Notification.Name("NewWorkRequested"), object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
            CommandMenu("Attendance") {
                Button("Open Attendance") {
                    NotificationCenter.default.post(name: Notification.Name("OpenAttendanceRequested"), object: nil)
                }
            }
            CommandMenu("Troubleshooting") {
                #if os(macOS)
                Toggle(
                    "Allow Local Store Fallback",
                    isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: MariasToolboxApp.allowLocalStoreFallbackKey) },
                        set: { UserDefaults.standard.set($0, forKey: MariasToolboxApp.allowLocalStoreFallbackKey) }
                    )
                )
                #endif
                Button("Use In-Memory Store On Next Launch") {
                    UserDefaults.standard.set(true, forKey: MariasToolboxApp.useInMemoryFlagKey)
                    #if os(macOS)
                    NSApp.requestUserAttention(.criticalRequest)
                    #endif
                    print("Set toggle: App will use in-memory SwiftData store on next launch.")
                }
                Button("Reset Persistent Store…") {
                    do {
                        try MariasToolboxApp.resetPersistentStore()
                        print("SwiftData: Persistent store reset. Quit and relaunch the app to recreate a fresh store.")
                        #if os(macOS)
                        NSApp.requestUserAttention(.criticalRequest)
                        #endif
                    } catch {
                        print("SwiftData: Failed to reset persistent store:", error)
                    }
                }
            }
        }

        #if os(macOS)
        WindowGroup("", id: "WorkDetailWindow", for: UUID.self) { $workID in
            if let id = workID {
                WorkDetailWindowContainer(workID: id)
                    .environment(\.calendar, AppCalendar.shared)
                    .environmentObject(saveCoordinator)
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

