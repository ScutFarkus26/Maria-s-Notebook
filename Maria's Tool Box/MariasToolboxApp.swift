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
    
    // Track initialization errors to show in the UI
    static var initError: Error?

    @StateObject private var saveCoordinator = SaveCoordinator()
    @StateObject private var bootstrapper = AppBootstrapper.shared

    static func resetPersistentStore() throws {
        let url = storeFileURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    static func storeFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "MariasToolbox"
        let containerDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fm.createDirectory(at: containerDir, withIntermediateDirectories: true)
        // IMPORTANT: return a file URL for the SwiftData store package. Do not pre-create it.
        return containerDir.appendingPathComponent("SwiftData.store", isDirectory: false)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = AppSchema.schema
        let useInMemory = UserDefaults.standard.bool(forKey: MariasToolboxApp.useInMemoryFlagKey)
        let allowFallback = UserDefaults.standard.bool(forKey: MariasToolboxApp.allowLocalStoreFallbackKey)
        
        // Helper to create container
        func makeContainer(inMemory: Bool, url: URL? = nil, cloud: Bool = false) throws -> ModelContainer {
            if inMemory {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: config)
            } else if cloud {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.mariastoolbox"))
                return try ModelContainer(for: schema, configurations: config)
            } else {
                let config = ModelConfiguration(url: url ?? MariasToolboxApp.storeFileURL())
                return try ModelContainer(for: schema, configurations: config)
            }
        }

        do {
            if useInMemory {
                let container = try makeContainer(inMemory: true)
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set("Using temporary in-memory store on next launch.", forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
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
                    // STOP: Do not silently fallback unless explicitly allowed.
                    if allowFallback {
                        print("SwiftData: CloudKit failed, performing INTENTIONAL local fallback. Error: \(error)")
                        let container = try makeContainer(inMemory: false)
                        UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                        UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                        return container
                    } else {
                        // Capture error and return a safe, empty in-memory container
                        // so the app launches to the Error View instead of crashing.
                        print("SwiftData: CloudKit failed. HALTING to prevent split-brain. Error: \(error)")
                        UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                        UserDefaults.standard.set(error.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                        MariasToolboxApp.initError = error
                        return try makeContainer(inMemory: true)
                    }
                }
            }
        } catch {
            // If even the in-memory fallback fails, we must surface the blocking error view instead of crashing.
            print("SwiftData: Failed to open SwiftData store even for fallback: \(error)")
            MariasToolboxApp.initError = error
            UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
            UserDefaults.standard.set(error.localizedDescription, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            // As a last resort, create an empty in-memory container so the app can show the blocking error view
            do {
                let empty = Schema([])
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: empty, configurations: config)
            } catch {
                fatalError("Failed to create even an empty in-memory SwiftData container: \(error)")
            }
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
