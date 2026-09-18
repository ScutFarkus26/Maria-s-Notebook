//
//  MCPRequestHandler.swift
//  Cosmic Daybook
//
//  Dispatches decoded MCP JSON-RPC messages: lifecycle (initialize/ping),
//  tool discovery (tools/list), and tool execution (tools/call).
//  Platform-neutral and transport-agnostic so it can be unit tested
//  without a socket.
//

import Foundation

/// Handles one MCP client's requests. Stateless between messages: the
/// server is lenient about lifecycle ordering, which makes it robust
/// against clients that skip or repeat the initialize handshake.
struct MCPRequestHandler: Sendable {
    /// Protocol revisions this server can speak, newest first.
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let serverVersion: String
    let tools: [MCPToolDefinition]
    /// Called once for every successful call of a tool that changes the
    /// notebook, so provenance can be journalled without any entity field
    /// having to carry it. Never called for reads or for failures.
    let onWrite: (@Sendable (MCPWriteRecord) async -> Void)?

    init(
        serverVersion: String,
        tools: [MCPToolDefinition],
        onWrite: (@Sendable (MCPWriteRecord) async -> Void)? = nil
    ) {
        self.serverVersion = serverVersion
        self.tools = tools
        self.onWrite = onWrite
    }

    /// Handles one newline-delimited JSON-RPC message.
    /// Returns the encoded response, or nil when no response is due
    /// (notifications, and unrecognized notifications).
    func handle(line: Data) async -> Data? {
        let request: JSONRPCRequest
        do {
            request = try JSONDecoder().decode(JSONRPCRequest.self, from: line)
        } catch {
            return encode(.failure(id: nil, code: JSONRPCErrorCode.parseError, message: "Parse error"))
        }

        guard request.jsonrpc == "2.0" else {
            return encode(.failure(
                id: request.id, code: JSONRPCErrorCode.invalidRequest,
                message: "Unsupported JSON-RPC version"
            ))
        }

        // Notifications (no id) never receive a response.
        if request.isNotification {
            return nil
        }

        let response = await respond(to: request)
        return encode(response)
    }

    private func respond(to request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return initializeResponse(for: request)
        case "ping":
            return .success(id: request.id, result: .object([:]))
        case "tools/list":
            return toolsListResponse(for: request)
        case "tools/call":
            return await toolsCallResponse(for: request)
        default:
            return .failure(
                id: request.id, code: JSONRPCErrorCode.methodNotFound,
                message: "Method not found: \(request.method)"
            )
        }
    }

    // MARK: - Lifecycle

    private func initializeResponse(for request: JSONRPCRequest) -> JSONRPCResponse {
        // Version negotiation: echo the client's version when supported,
        // otherwise offer our newest.
        let requested = request.params?["protocolVersion"]?.stringValue
        let negotiated = Self.supportedProtocolVersions.first { $0 == requested }
            ?? Self.supportedProtocolVersions[0]

        let result: JSONValue = .object([
            "protocolVersion": .string(negotiated),
            "capabilities": ["tools": [:]],
            "serverInfo": .object([
                "name": "cosmic-daybook",
                "title": "Cosmic Daybook",
                "version": .string(serverVersion)
            ]),
            "instructions": .string(Self.serverInstructions)
        ])
        return .success(id: request.id, result: result)
    }

    private static let serverInstructions = """
        Cosmic Daybook is a Montessori classroom management app. These tools read and record \
        real classroom data — students, lesson presentations, observations, student meetings, \
        follow-ups, work, attendance, and todos — from the teacher's live notebook. Dates use \
        ISO 8601 (YYYY-MM-DD). Treat student information as sensitive and only surface what \
        the teacher asks for.
        """

    // MARK: - Tools

    private func toolsListResponse(for request: JSONRPCRequest) -> JSONRPCResponse {
        let descriptors: [JSONValue] = tools.map { tool in
            .object([
                "name": .string(tool.name),
                "title": .string(tool.title),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema,
                "annotations": tool.annotations.jsonValue
            ])
        }
        return .success(id: request.id, result: .object(["tools": .array(descriptors)]))
    }

    private func toolsCallResponse(for request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let name = request.params?["name"]?.stringValue else {
            return .failure(
                id: request.id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call requires a tool name"
            )
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return .failure(
                id: request.id, code: JSONRPCErrorCode.invalidParams,
                message: "Unknown tool: \(name)"
            )
        }

        let arguments = request.params?["arguments"]?.objectValue ?? [:]
        do {
            let text = try await tool.handler(arguments)
            // Only a call that returned — a thrown error falls to the catch —
            // and only one that could have changed something.
            if let onWrite, !tool.annotations.readOnlyHint {
                await onWrite(MCPWriteRecord(
                    tool: tool.name, arguments: arguments, result: text,
                    destructive: tool.annotations.destructiveHint
                ))
            }
            return .success(id: request.id, result: Self.toolResult(text: text, isError: false))
        } catch {
            let message = (error as? MCPToolError)?.message ?? error.localizedDescription
            return .success(id: request.id, result: Self.toolResult(text: message, isError: true))
        }
    }

    private static func toolResult(text: String, isError: Bool) -> JSONValue {
        .object([
            "content": .array([
                .object(["type": "text", "text": .string(text)])
            ]),
            "isError": .bool(isError)
        ])
    }

    // MARK: - Encoding

    private func encode(_ response: JSONRPCResponse) -> Data? {
        // Default JSONEncoder output contains no raw newlines, which the
        // newline-delimited transport requires.
        try? JSONEncoder().encode(response)
    }
}
