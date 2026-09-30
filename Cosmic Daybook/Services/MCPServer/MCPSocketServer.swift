//
//  MCPSocketServer.swift
//  Cosmic Daybook
//
//  Listens on loopback TCP and speaks newline-delimited JSON-RPC (the MCP
//  stdio framing) with each connected client. Claude Desktop reaches this
//  port through the bridge script in Scripts/mcp/.
//
//  Why TCP and not a Unix domain socket: the App Sandbox only permits
//  binding Unix sockets inside the app's (group) container, and macOS
//  container protection TCC-gates those paths for every external client.
//  Loopback TCP with the incoming-connections entitlement is the
//  sanctioned path. A per-install token (readable only by this user)
//  authenticates each connection before any MCP traffic is processed.
//
//  macOS only: Claude Desktop runs on the Mac.
//

#if os(macOS)
import Foundation
import Network
import OSLog
import Synchronization

/// Accepts local TCP connections, checks the auth token, and runs the MCP
/// message loop for each client.
actor MCPSocketServer {
    /// Safety cap on a single buffered message; a well-formed MCP line
    /// should be far smaller.
    private static let maximumLineLength = 10 * 1024 * 1024

    private let port: UInt16
    private let authToken: String
    private let requestHandler: MCPRequestHandler
    /// Called if the listener dies after it was ready (never for a plain
    /// `stop()`), so the owning service can stop reporting "listening".
    private let onFailure: (@Sendable (String) -> Void)?
    /// Called with the number of connected clients (those past the `AUTH`
    /// line) whenever it changes, with a sequence number that rises on every
    /// call, so a receiver that hops actors can drop an update overtaken by a
    /// newer one. An MCP-only launch quits once this has been zero for a while.
    private let onClientCountChange: (@Sendable (_ count: Int, _ sequence: Int) -> Void)?
    private let queue = DispatchQueue(label: "mcp-server.socket")
    private let logger = Logger.mcpServer

    private var listener: NWListener?
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Held so `stop()` can cancel them: a message loop waiting in `receive`
    /// doesn't see its task's cancellation until the connection closes.
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var authenticatedClients: Set<ObjectIdentifier> = []
    private var clientCountSequence = 0

    init(
        port: UInt16,
        authToken: String,
        requestHandler: MCPRequestHandler,
        onFailure: (@Sendable (String) -> Void)? = nil,
        onClientCountChange: (@Sendable (_ count: Int, _ sequence: Int) -> Void)? = nil
    ) {
        self.port = port
        self.authToken = authToken
        self.requestHandler = requestHandler
        self.onFailure = onFailure
        self.onClientCountChange = onClientCountChange
    }

    // MARK: - Lifecycle

    /// Returns once the listener is actually accepting connections, and
    /// throws if the bind fails — e.g. the port is already held by another
    /// running copy of the app. NWListener only reports that asynchronously,
    /// so a fire-and-forget start would look successful while nothing
    /// listens.
    func start() async throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        // Bind strictly to loopback: never reachable from the network.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in await self?.adopt(connection) }
        }
        self.listener = listener

        // The continuation must resume exactly once, but the handler keeps
        // firing for the listener's whole life; the mutex claims the first
        // terminal transition and later ones take the running-failure path.
        let resumed = Mutex(false)
        @Sendable func claimFirstTransition() -> Bool {
            resumed.withLock { alreadyResumed in
                if alreadyResumed { return false }
                alreadyResumed = true
                return true
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                listener.stateUpdateHandler = { [weak self, port, logger] state in
                    switch state {
                    case .ready:
                        logger.notice("MCP server listening on 127.0.0.1:\(port, privacy: .public)")
                        if claimFirstTransition() { continuation.resume() }
                    case .failed(let error):
                        logger.error("MCP listener failed: \(error, privacy: .public)")
                        if claimFirstTransition() {
                            continuation.resume(throwing: error)
                        } else {
                            Task { [weak self] in await self?.listenerDidFail(error.localizedDescription) }
                        }
                    case .cancelled:
                        if claimFirstTransition() { continuation.resume(throwing: CancellationError()) }
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        } catch {
            self.listener = nil
            listener.cancel()
            throw error
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for task in connectionTasks.values {
            task.cancel()
        }
        connectionTasks.removeAll()
        // Close the sockets too, so no loop receives another line (and runs
        // another tool) after the server was turned off.
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        // The owner stops counting a stopped server's clients itself.
        authenticatedClients.removeAll()
    }

    // MARK: - Connections

    private func adopt(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: queue)
        let didAuthenticate: @Sendable () async -> Void = { [weak self] in
            await self?.clientDidAuthenticate(id)
        }
        connectionTasks[id] = Task { [weak self, requestHandler, authToken, logger] in
            await Self.runMessageLoop(
                on: connection, handler: requestHandler, authToken: authToken, logger: logger,
                didAuthenticate: didAuthenticate
            )
            connection.cancel()
            await self?.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) {
        connectionTasks[id] = nil
        connections[id] = nil
        if authenticatedClients.remove(id) != nil {
            publishClientCount()
        }
    }

    private func clientDidAuthenticate(_ id: ObjectIdentifier) {
        // A connection whose task `stop()` already cancelled is not counted.
        guard connectionTasks[id] != nil else { return }
        authenticatedClients.insert(id)
        publishClientCount()
    }

    private func publishClientCount() {
        clientCountSequence += 1
        onClientCountChange?(authenticatedClients.count, clientCountSequence)
    }

    /// A ready listener died on its own (not via `stop()`); tear down and
    /// tell the owner so status stops claiming the server is listening.
    private func listenerDidFail(_ message: String) {
        stop()
        onFailure?(message)
    }

    /// Reads newline-delimited messages and writes back responses until
    /// the client disconnects. The first line must be `AUTH <token>`;
    /// anything else closes the connection before any MCP processing.
    private static func runMessageLoop(
        on connection: NWConnection,
        handler: MCPRequestHandler,
        authToken: String,
        logger: Logger,
        didAuthenticate: @Sendable () async -> Void
    ) async {
        var buffer = Data()
        var authenticated = false
        do {
            while !Task.isCancelled {
                guard let chunk = try await receive(on: connection) else { break }
                buffer.append(chunk)
                guard buffer.count <= maximumLineLength else { break }

                // A stopped server dispatches nothing more, even a line that
                // arrived in the same chunk as the last one it ran.
                while !Task.isCancelled, let line = nextLine(from: &buffer) {
                    if !authenticated {
                        guard String(bytes: line, encoding: .utf8) == "AUTH \(authToken)" else {
                            logger.warning("MCP client rejected: bad auth preamble")
                            return
                        }
                        authenticated = true
                        // notice, not info: info never reaches the log
                        // archive, and "did a client ever connect" is the
                        // first question when diagnosing this feature.
                        logger.notice("MCP client connected")
                        await didAuthenticate()
                        continue
                    }

                    if var response = await handler.handle(line: line) {
                        response.append(UInt8(ascii: "\n"))
                        try await send(response, on: connection)
                    }
                }
            }
        } catch {
            // Disconnects surface as receive/send errors; nothing to do.
        }
        if authenticated {
            logger.notice("MCP client disconnected")
        }
    }

    /// Removes and returns the next non-empty line (without its newline),
    /// or nil when no complete line is buffered yet.
    private static func nextLine(from buffer: inout Data) -> Data? {
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(buffer.prefix(upTo: newlineIndex))
            buffer.removeSubrange(...newlineIndex)
            if !line.isEmpty { return line }
        }
        return nil
    }

    private static func receive(on connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
#endif
