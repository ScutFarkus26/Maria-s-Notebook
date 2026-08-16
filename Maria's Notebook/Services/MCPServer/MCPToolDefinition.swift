//
//  MCPToolDefinition.swift
//  Maria's Notebook
//
//  Describes one tool the MCP server exposes to connected clients
//  (e.g. Claude Desktop). Handlers run on the main actor because they
//  read and write Core Data through the app's repositories and services.
//

import Foundation

/// A tool exposed over MCP: metadata for `tools/list` plus the handler
/// invoked by `tools/call`.
struct MCPToolDefinition: Sendable {
    let name: String
    let title: String
    let description: String
    /// JSON Schema for the tool's arguments (an `object` schema).
    let inputSchema: JSONValue
    /// Executes the tool. Runs on the main actor so it can use the
    /// app's `@MainActor` repositories and services directly.
    let handler: @MainActor @Sendable ([String: JSONValue]) async throws -> String
}

/// An error whose message is safe and useful to show to the calling model.
/// Thrown by tool handlers for expected failures (bad arguments, missing
/// records); reported as a tool execution error (`isError: true`), not a
/// protocol error.
struct MCPToolError: Error, LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
