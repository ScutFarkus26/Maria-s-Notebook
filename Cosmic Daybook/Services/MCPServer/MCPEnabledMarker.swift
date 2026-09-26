//
//  MCPEnabledMarker.swift
//  Cosmic Daybook
//
//  The file the MCP bridge (Scripts/mcp/cosmic-daybook-mcp) checks before it
//  launches the app: `~/.cosmic-daybook/enabled`, present exactly while
//  Settings → AI Features → "Allow Claude Desktop Access" is on. The toggle
//  lives in the app's sandboxed defaults, which the script cannot read, and
//  without the marker it launched the app for a server that would never
//  listen. MCPServerService keeps the marker in step at launch and on every
//  toggle. Platform-neutral so the file handling is testable on iOS.
//

import Foundation

nonisolated enum MCPEnabledMarker {
    static let fileName = "enabled"

    static func path(in directory: String) -> String {
        (directory as NSString).appendingPathComponent(fileName)
    }

    /// Creates the marker (0600, in a 0700 directory, like the auth token)
    /// or removes it, to match `enabled`. Idempotent.
    static func sync(enabled: Bool, in directory: String) throws {
        let manager = FileManager.default
        let marker = path(in: directory)
        if enabled {
            guard !manager.fileExists(atPath: marker) else { return }
            try manager.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard manager.createFile(atPath: marker, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: marker])
            }
        } else if manager.fileExists(atPath: marker) {
            try manager.removeItem(atPath: marker)
        }
    }
}
