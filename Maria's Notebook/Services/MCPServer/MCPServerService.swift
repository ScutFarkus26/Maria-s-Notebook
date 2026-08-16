//
//  MCPServerService.swift
//  Maria's Notebook
//
//  Lifecycle owner for the in-app MCP server. Started from
//  performStartupBootstrap on macOS when the Settings toggle is on;
//  the Settings pane starts and stops it live via applySettings().
//

#if os(macOS)
import Foundation
import OSLog

/// Starts and stops the MCP server according to the user's "Claude
/// Desktop access" setting, and publishes status for Settings.
@MainActor
@Observable
final class MCPServerService {
    static let shared = MCPServerService()

    /// Fixed loopback port the server binds; the bridge script uses the
    /// same constant. Change both together.
    static let port: UInt16 = 43117

    private(set) var isRunning = false
    private(set) var lastError: String?

    private var server: MCPSocketServer?
    private let logger = Logger.app(category: "MCPServer")

    private init() {}

    /// Directory shared with the bridge script for the auth token.
    /// Lives in the user's *real* home (granted by a scoped
    /// temporary-exception entitlement) — NSHomeDirectory() would be the
    /// sandbox container, which external processes cannot read.
    nonisolated static var supportDirectory: String {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return home + "/.marias-notebook"
    }

    nonisolated static var tokenPath: String { supportDirectory + "/mcp.token" }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.aiMCPServerEnabled)
    }

    /// Reconciles the running state with the Settings toggle.
    func applySettings() {
        if isEnabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard server == nil else { return }
        do {
            let token = try Self.loadOrCreateToken()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0"
            let handler = MCPRequestHandler(serverVersion: version, tools: MCPNotebookTools.makeTools())
            let server = MCPSocketServer(port: Self.port, authToken: token, requestHandler: handler)
            self.server = server
            Task {
                do {
                    try await server.start()
                    isRunning = true
                    lastError = nil
                } catch {
                    logger.error("MCP server failed to start: \(error, privacy: .public)")
                    self.server = nil
                    isRunning = false
                    lastError = error.localizedDescription
                }
            }
        } catch {
            logger.error("MCP token setup failed: \(error, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    private func stop() {
        guard let server else { return }
        self.server = nil
        isRunning = false
        Task { await server.stop() }
    }

    /// Returns the persistent per-install auth token, creating it (0600,
    /// in a 0700 directory) on first run. The bridge script sends it as
    /// an `AUTH` preamble line; it never leaves this Mac.
    private static func loadOrCreateToken() throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(
            atPath: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if let existing = try? String(contentsOfFile: tokenPath, encoding: .utf8) {
            let token = existing.trimmed()
            if !token.isEmpty { return token }
        }
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        try token.write(toFile: tokenPath, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenPath)
        return token
    }
}
#endif
