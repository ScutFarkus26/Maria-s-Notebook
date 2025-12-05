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

    /// Remove the persistent store directory to allow the app to recreate a fresh store on next launch.
    /// This is destructive and should be used only when the store is corrupted/incompatible.
    static func resetPersistentStore() throws {
        let url = storeDirectoryURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schemaTypes: [any PersistentModel.Type] = [
            Item.self,
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCompletionRecord.self,
            AttendanceRecord.self,
            WorkCheckIn.self,
            NonSchoolDay.self,
            SchoolDayOverride.self
        ]
        let useInMemory = UserDefaults.standard.bool(forKey: MariasToolboxApp.useInMemoryFlagKey)
        do {
            if useInMemory {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: Schema(schemaTypes), configurations: config)
                UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.set("Using in-memory store by user toggle.", forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                UserDefaults.standard.set(false, forKey: MariasToolboxApp.useInMemoryFlagKey)
                print("SwiftData: Using in-memory store for this launch (toggle enabled).")
                return container
            } else {
                // Use an explicit on-disk location so the store can be reset if it becomes incompatible
                let config = ModelConfiguration(url: MariasToolboxApp.storeDirectoryURL())
                let container = try ModelContainer(for: Schema(schemaTypes), configurations: config)
                UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
                UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                return container
            }
        } catch {
            let ns = error as NSError
            print("SwiftData container error:", error)
            print("userInfo:", ns.userInfo)
            UserDefaults.standard.set(true, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
            var message = "\(ns.domain) code=\(ns.code): \(ns.localizedDescription)"
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                message += " | underlying: \(underlying.domain) code=\(underlying.code): \(underlying.localizedDescription)"
            }
            UserDefaults.standard.set(message, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
            // In DEBUG, fall back to in-memory so the app can launch and you can repair/migrate.
            // In RELEASE, fail loudly to avoid silent data loss across launches.
            #if DEBUG
                do {
                    let config = ModelConfiguration(isStoredInMemoryOnly: true)
                    let fallback = try ModelContainer(for: Schema(schemaTypes), configurations: config)
                    print("SwiftData: Falling back to in-memory store due to error. Data won't persist this session.")
                    if UserDefaults.standard.string(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey) == nil {
                        let ns3 = error as NSError
                        var msg = "\(ns3.domain) code=\(ns3.code): \(ns3.localizedDescription)"
                        if let underlying = ns3.userInfo[NSUnderlyingErrorKey] as? NSError {
                            msg += " | underlying: \(underlying.domain) code=\(underlying.code): \(underlying.localizedDescription)"
                        }
                        UserDefaults.standard.set(msg, forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
                    }
                    return fallback
                } catch {
                    let ns2 = error as NSError
                    print("SwiftData in-memory fallback error:", error)
                    print("userInfo:", ns2.userInfo)
                    // Keep flags set; crash as a last resort.
                    fatalError("Failed to create persistent ModelContainer (including in-memory fallback): \(error)")
                }
            #else
                // In release builds, avoid silently running in-memory. Surface the error and stop.
                fatalError("Failed to open persistent SwiftData store: \(error). Delete and reinstall the app, then restore from backup.")
            #endif
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
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
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
            } else {
                Text("No work selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(sharedModelContainer)
        #endif
    }
}

