import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - The bridge's "Claude access is on" marker
//
// The bridge script launches the app only when `~/.cosmic-daybook/enabled`
// exists; the app creates it while "Allow Claude Desktop Access" is on and
// removes it when the toggle goes off. These tests run the same file handling
// against a temporary directory.

@Suite("MCP enabled marker")
struct MCPEnabledMarkerTests {
    private static func temporaryDirectory() -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPEnabledMarkerTests-\(UUID().uuidString)", isDirectory: true)
        // The marker's directory is created on demand, like ~/.cosmic-daybook.
        return root.appendingPathComponent(".cosmic-daybook", isDirectory: true).path
    }

    private static func permissions(atPath path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test("Turning access on creates the marker, owner-only, in an owner-only directory")
    func enablingCreatesMarker() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: (directory as NSString).deletingLastPathComponent) }
        let marker = MCPEnabledMarker.path(in: directory)

        try MCPEnabledMarker.sync(enabled: true, in: directory)

        #expect(marker.hasSuffix("/.cosmic-daybook/enabled"))
        #expect(FileManager.default.fileExists(atPath: marker))
        #expect(try Self.permissions(atPath: marker) == 0o600)
        #expect(try Self.permissions(atPath: directory) == 0o700)
    }

    @Test("Turning access off removes it, and both directions are idempotent")
    func disablingRemovesMarker() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: (directory as NSString).deletingLastPathComponent) }
        let marker = MCPEnabledMarker.path(in: directory)

        try MCPEnabledMarker.sync(enabled: false, in: directory)   // nothing there yet
        #expect(!FileManager.default.fileExists(atPath: marker))

        try MCPEnabledMarker.sync(enabled: true, in: directory)
        try MCPEnabledMarker.sync(enabled: true, in: directory)
        #expect(FileManager.default.fileExists(atPath: marker))

        try MCPEnabledMarker.sync(enabled: false, in: directory)
        try MCPEnabledMarker.sync(enabled: false, in: directory)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("It leaves the auth token beside it alone")
    func tokenUntouched() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: (directory as NSString).deletingLastPathComponent) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let token = (directory as NSString).appendingPathComponent("mcp.token")
        try "secret".write(toFile: token, atomically: true, encoding: .utf8)

        try MCPEnabledMarker.sync(enabled: true, in: directory)
        try MCPEnabledMarker.sync(enabled: false, in: directory)

        #expect(try String(contentsOfFile: token, encoding: .utf8) == "secret")
    }
}
