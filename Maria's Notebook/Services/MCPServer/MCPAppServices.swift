//
//  MCPAppServices.swift
//  Maria's Notebook
//
//  The one place the MCP layer can reach app-level services. `AppDependencies`
//  is injected into the SwiftUI environment, which a static tool handler
//  cannot see; the app registers it here once at startup, before the MCP
//  server starts, and the tools that need a backup manager or a report
//  drafter read it back. Tests register a dependencies object built on an
//  in-memory stack, or nothing, in which case those tools say the app is
//  still starting.
//

import Foundation

/// Supplies the app's dependency container to tools that need more than a
/// managed object context. Injectable so tests can point the tools at a
/// container built on an in-memory stack.
typealias MCPDependenciesProvider = @MainActor @Sendable () -> AppDependencies?

enum MCPAppServices {
    /// The container the running app registered, or nil before startup and
    /// under unit tests.
    private(set) static var dependencies: AppDependencies?

    static func register(_ dependencies: AppDependencies) {
        Self.dependencies = dependencies
    }
}
