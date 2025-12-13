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
    @StateObject private var bootstrapper = AppBootstrapper.shared

    static func resetPersistentStore() throws {
        let url = storeDirectoryURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    static func storeDirectoryURL() -> URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "MariasToolbox"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("SwiftDataStore", isDirectory: true)
        try? fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        return dir
    }

    var sharedModelContainer: ModelContainer = {
        let schema = AppSchema.schema
        let useInMemory = UserDefaults.standard.bool(forKey: MariasToolboxApp.useInMemoryFlagKey)
        
        // Helper to create container
        func makeContainer(inMemory: Bool, url: URL? = nil, cloud: Bool = false) throws -> ModelContainer {
            if inMemory {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: config)
            } else if cloud {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.mariastoolbox"))
                return try ModelContainer(for: schema, configurations: config)
            } else {
                let config = ModelConfiguration(url: url ?? MariasToolboxApp.storeDirectoryURL())
                return try ModelContainer(for: schema, configurations: config)
            }
        }

        do {
            if useInMemory {
                let container = try makeContainer(inMemory: true)
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set(false, forKey: MariasToolboxApp.useInMemoryFlagKey)
                print("SwiftData: Using in-memory store.")
                return container
            } else {
                do {
                    // Try CloudKit
                    let container = try makeContainer(inMemory: false, cloud: true)
                    UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                    UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                    return container
                } catch {
                    // Fallback to Local
                    print("SwiftData: CloudKit failed, attempting local fallback. Error: \(error)")
                    let container = try makeContainer(inMemory: false)
                    UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                    return container
                }
            }
        } catch {
            fatalError("Failed to open SwiftData store: \(error)")
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
            Group {
                if bootstrapper.state == .ready {
                    RootView()
                        .environment(\.calendar, AppCalendar.shared)
                        .environmentObject(saveCoordinator)
                } else {
                    // Loading / Splash Screen
                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Preparing Database...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Ensure you have a 'baseBackground' color in your assets, or change this to .background
                    .background(Color.clear)
                }
            }
            .task {
                await bootstrapper.bootstrap(modelContainer: sharedModelContainer)
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
