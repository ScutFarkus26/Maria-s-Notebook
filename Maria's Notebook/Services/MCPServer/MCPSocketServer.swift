//
//  MCPSocketServer.swift
//  Maria's Notebook
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

/// Accepts local TCP connections, checks the auth token, and runs the MCP
/// message loop for each client.
actor MCPSocketServer {
    /// Safety cap on a single buffered message; a well-formed MCP line
    /// should be far smaller.
    private static let maximumLineLength = 10 * 1024 * 1024

    private let port: UInt16
    private let authToken: String
    private let requestHandler: MCPRequestHandler
    private let queue = DispatchQueue(label: "mcp-server.socket")
    private let logger = Logger.app(category: "MCPServer")

    private var listener: NWListener?
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(port: UInt16, authToken: String, requestHandler: MCPRequestHandler) {
        self.port = port
        self.authToken = authToken
        self.requestHandler = requestHandler
    }

    var isRunning: Bool { listener != nil }

    // MARK: - Lifecycle

    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        // Bind strictly to loopback: never reachable from the network.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self, port, logger] state in
            switch state {
            case .ready:
                logger.info("MCP server listening on 127.0.0.1:\(port, privacy: .public)")
            case .failed(let error):
                logger.error("MCP listener failed: \(error, privacy: .public)")
                Task { [weak self] in await self?.stop() }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in await self?.adopt(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for task in connectionTasks.values {
            task.cancel()
        }
        connectionTasks.removeAll()
    }

    // MARK: - Connections

    private func adopt(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.start(queue: queue)
        connectionTasks[id] = Task { [weak self, requestHandler, authToken, logger] in
            await Self.runMessageLoop(
                on: connection, handler: requestHandler, authToken: authToken, logger: logger
            )
            connection.cancel()
            await self?.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) {
        connectionTasks[id] = nil
    }

    /// Reads newline-delimited messages and writes back responses until
    /// the client disconnects. The first line must be `AUTH <token>`;
    /// anything else closes the connection before any MCP processing.
    private static func runMessageLoop(
        on connection: NWConnection,
        handler: MCPRequestHandler,
        authToken: String,
        logger: Logger
    ) async {
        var buffer = Data()
        var authenticated = false
        do {
            while !Task.isCancelled {
                guard let chunk = try await receive(on: connection) else { break }
                buffer.append(chunk)
                guard buffer.count <= maximumLineLength else { break }

                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = Data(buffer.prefix(upTo: newlineIndex))
                    buffer.removeSubrange(...newlineIndex)
                    guard !line.isEmpty else { continue }

                    if !authenticated {
                        guard String(bytes: line, encoding: .utf8) == "AUTH \(authToken)" else {
                            logger.warning("MCP client rejected: bad auth preamble")
                            return
                        }
                        authenticated = true
                        logger.info("MCP client connected")
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
            logger.info("MCP client disconnected")
        }
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
