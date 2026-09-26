//
//  MCPServerService.swift
//  Cosmic Daybook
//
//  Lifecycle owner for the in-app MCP server. Started once per process by
//  AppServicesLauncher on macOS when the Settings toggle is on; the
//  Settings pane starts and stops it live via applySettings().
//

#if os(macOS)
import Foundation
import OSLog

/// Starts and stops the MCP server according to the user's "Claude
/// Desktop access" setting, and publishes status for Settings.
@Observable
final class MCPServerService {
    static let shared = MCPServerService()

    /// Fixed loopback port the server binds; the bridge script uses the
    /// same constant. Change both together.
    static let port: UInt16 = 43117

    private(set) var isRunning = false
    private(set) var lastError: String?
    /// Claude clients connected to the running server right now.
    private(set) var connectedClientCount = 0
    /// Told each time `connectedClientCount` changes. An MCP-only launch's
    /// idle quit (MCPIdleQuitController) is the one listener.
    @ObservationIgnored var onConnectedClientCountChange: ((Int) -> Void)?

    private var server: MCPSocketServer?
    /// Identifies the start attempt each async status update belongs to,
    /// so a stale readiness or failure can't clobber a newer server's state.
    private var currentServerID: UUID?
    /// The newest client-count update applied from the current server.
    @ObservationIgnored private var clientCountSequence = 0
    private let logger = Logger.mcpServer

    private init() {}

    /// Directory shared with the bridge script for the auth token.
    /// Lives in the user's *real* home (granted by a scoped
    /// temporary-exception entitlement) — NSHomeDirectory() would be the
    /// sandbox container, which external processes cannot read.
    nonisolated static var supportDirectory: String {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return home + "/.cosmic-daybook"
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
            let journal = MCPWriteJournal.shared
            let handler = MCPRequestHandler(
                serverVersion: version,
                tools: MCPNotebookTools.makeTools(journal: journal),
                onWrite: { record in await journal.record(record) }
            )
            let serverID = UUID()
            let server = MCPSocketServer(
                port: Self.port,
                authToken: token,
                requestHandler: handler,
                onFailure: { message in
                    Task { @MainActor in
                        MCPServerService.shared.serverDidFail(id: serverID, message: message)
                    }
                },
                onClientCountChange: { count, sequence in
                    Task { @MainActor in
                        MCPServerService.shared.clientCountDidChange(id: serverID, count: count, sequence: sequence)
                    }
                }
            )
            self.server = server
            currentServerID = serverID
            clientCountSequence = 0
            Task {
                do {
                    try await server.start()
                    guard currentServerID == serverID else { return }
                    isRunning = true
                    lastError = nil
                } catch {
                    logger.error("MCP server failed to start: \(error, privacy: .public)")
                    guard currentServerID == serverID else { return }
                    self.server = nil
                    currentServerID = nil
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
        currentServerID = nil
        isRunning = false
        setConnectedClientCount(0)
        Task { await server.stop() }
    }

    /// Closes the port ahead of an MCP-only launch's idle quit (the Settings
    /// toggle is left alone), so a Claude session that starts while the quit
    /// backup runs finds no listener, and its bridge starts a fresh copy once
    /// this one has exited, rather than connecting to a process about to go.
    func stopBeforeQuit() {
        stop()
    }

    /// A previously-ready listener died (the socket server already tore
    /// itself down); surface that in Settings instead of a stale green
    /// "Listening" row.
    private func serverDidFail(id: UUID, message: String) {
        guard currentServerID == id else { return }
        server = nil
        currentServerID = nil
        isRunning = false
        lastError = message
        setConnectedClientCount(0)
    }

    /// Applies a client count from the current server, unless a newer one
    /// already arrived (each hop to the main actor is its own task).
    private func clientCountDidChange(id: UUID, count: Int, sequence: Int) {
        guard currentServerID == id, sequence > clientCountSequence else { return }
        clientCountSequence = sequence
        setConnectedClientCount(count)
    }

    private func setConnectedClientCount(_ count: Int) {
        guard count != connectedClientCount else { return }
        connectedClientCount = count
        onConnectedClientCountChange?(count)
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
