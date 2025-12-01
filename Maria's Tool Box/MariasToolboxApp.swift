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
    init() {
        #if os(macOS)
        if let icon = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkModel.self,
            WorkCompletionRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
#if DEBUG
            print("Warning: Could not create persistent ModelContainer: \(error). Falling back to in-memory store.")
#endif
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
    }()

    var body: some Scene {
        WindowGroup("") {
            RootView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .modelContainer(sharedModelContainer)

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

