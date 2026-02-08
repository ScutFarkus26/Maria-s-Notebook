//
//  Logger+Extensions.swift
//  Maria's Notebook
//
//  Created by Refactoring on 2/8/26.
//

import OSLog

extension Logger {
    /// Creates a logger for the app with the specified category.
    /// Uses the main bundle identifier as the subsystem, falling back to "com.mariasnotebook" if unavailable.
    static func app(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: category)
    }
}
