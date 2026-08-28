//
//  MCPRequestHandler.swift
//  Maria's Notebook
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
                "name": "marias-notebook",
                "title": "Maria's Notebook",
                "version": .string(serverVersion)
            ]),
            "instructions": .string(Self.serverInstructions)
        ])
        return .success(id: request.id, result: result)
    }

    private static let serverInstructions = """
        Maria's Notebook is a Montessori classroom management app. These tools read and record \
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
                "inputSchema": tool.inputSchema
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
