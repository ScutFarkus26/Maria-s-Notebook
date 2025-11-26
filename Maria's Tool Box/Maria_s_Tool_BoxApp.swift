//
//  Maria_s_Tool_BoxApp.swift
//  Maria's Tool Box
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import SwiftData

@main
struct Maria_s_Tool_BoxApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Student.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
