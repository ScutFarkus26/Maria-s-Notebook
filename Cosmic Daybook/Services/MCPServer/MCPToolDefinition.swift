//
//  MCPToolDefinition.swift
//  Cosmic Daybook
//
//  Describes one tool the MCP server exposes to connected clients
//  (e.g. Claude Desktop). Handlers run on the main actor because they
//  read and write Core Data through the app's repositories and services.
//

import Foundation

/// The MCP `annotations` object: what a client may assume about calling
/// this tool (spec revision 2025-03-26 and later). Clients use these hints
/// for permission UX, so they are hints about *effects*, never a security
/// boundary — the handler itself still enforces every refusal and gate.
///
/// `title` is deliberately omitted: the server already emits a top-level
/// `title` for every tool, which takes precedence.
nonisolated struct MCPToolAnnotations: Sendable, Equatable {
    /// The tool does not change the notebook.
    let readOnlyHint: Bool
    /// The tool may delete or retire rows a guide would miss.
    let destructiveHint: Bool
    /// Calling twice with the same arguments leaves the same state.
    let idempotentHint: Bool
    /// Always false here: every tool reads the local notebook.
    let openWorldHint: Bool

    /// Reads only.
    static let readOnly = MCPToolAnnotations(
        readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false
    )
    /// Creates rows; calling twice may create twice (unless the tool documents its own dedup).
    static let write = MCPToolAnnotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false
    )
    /// Edits in place; calling twice with the same arguments leaves the same state.
    static let idempotentWrite = MCPToolAnnotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false
    )
    /// Deletes or retires rows.
    static let destructive = MCPToolAnnotations(
        readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false
    )

    /// The object `tools/list` carries for this tool.
    var jsonValue: JSONValue {
        .object([
            "readOnlyHint": .bool(readOnlyHint),
            "destructiveHint": .bool(destructiveHint),
            "idempotentHint": .bool(idempotentHint),
            "openWorldHint": .bool(openWorldHint)
        ])
    }
}

/// A tool exposed over MCP: metadata for `tools/list` plus the handler
/// invoked by `tools/call`.
struct MCPToolDefinition: Sendable {
    let name: String
    let title: String
    let description: String
    /// JSON Schema for the tool's arguments (an `object` schema).
    let inputSchema: JSONValue
    /// What a client may assume about calling this tool. No default, so
    /// every tool has to say what it does to the notebook.
    let annotations: MCPToolAnnotations
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
