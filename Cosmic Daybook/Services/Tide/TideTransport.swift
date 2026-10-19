// TideTransport.swift
// One Tide tool call: the seam the sync talks to Tide through.

import Foundation
import OSLog

/// One reply of a Tide tool: its content's text (Tide's JSON), and whether
/// Tide marked it an error — a refusal, with its rule and fix.
nonisolated struct TideToolReply: Sendable, Equatable {
    let text: String
    let isError: Bool
}

/// What the sync needs of Tide: one `tools/call`. `TideHTTPTransport` is the
/// only real one, on the Mac; tests pass a fake. A test never points at the
/// real server: a simulator reaches the Mac's `localhost`, which is Danny's
/// live Tide.
protocol TideTransport: AnyObject {
    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> TideToolReply
}

/// Why a call never reached a tool.
nonisolated enum TideTransportError: Error, Equatable, LocalizedError {
    /// Nothing answers at the address: Tide isn't open on this Mac.
    case notRunning
    /// Tide answered but took too long.
    case timedOut
    /// Tide refused the token in the address (HTTP 401): Tide made a new one.
    case tokenRefused
    /// Something answered that wasn't a reply Tide sends; the text is for the
    /// log and the Details disclosure only.
    case unexpectedReply(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: TideSyncMessages.tideNotRunning
        case .timedOut: TideSyncMessages.tideTimedOut
        case .tokenRefused: TideSyncMessages.tokenRefused
        case .unexpectedReply: TideSyncMessages.unexpectedReply
        }
    }
}

/// Tide's server on this Mac: MCP's Streamable HTTP, stateless. Each POST
/// carries one JSON-RPC request and gets one JSON reply — no event stream, no
/// session id (`StatelessHTTPServerTransport`; Tide's `MCPHTTPTransport`,
/// read 2026-10-18). Tide answers `initialize` for every client itself and
/// needs none before `tools/call`, so none is sent.
///
/// Every request carries its own id: Tide's transport matches replies to
/// requests by id across all its clients, so a counter starting at 1 could
/// meet Claude's own request 1.
final class TideHTTPTransport: TideTransport {
    private let address: TideAddress
    private let session: URLSession

    /// A version Tide's SDK supports (`Version.supported`); one it didn't would
    /// be refused with 400.
    static let protocolVersion = "2025-06-18"

    private static let logger = Logger(subsystem: "CosmicDaybook", category: "TideSync")

    init(address: TideAddress) {
        self.address = address
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    deinit { session.finishTasksAndInvalidate() }

    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> TideToolReply {
        let call = TideRPCCall(
            id: .string("daybook-\(UUID().uuidString)"),
            method: "tools/call",
            params: .object(["name": .string(name), "arguments": .object(arguments)])
        )
        var request = URLRequest(url: address.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try JSONEncoder().encode(call)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            Self.logger.notice("Tide call \(name, privacy: .public) failed: URLError \(error.code.rawValue)")
            throw Self.transportError(for: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TideTransportError.unexpectedReply("No HTTP response")
        }
        guard http.statusCode != 401 else {
            Self.logger.notice("Tide refused the saved token (401)")
            throw TideTransportError.tokenRefused
        }
        guard http.statusCode == 200 else {
            Self.logger.error("Tide call \(name, privacy: .public) answered HTTP \(http.statusCode)")
            throw TideTransportError.unexpectedReply("HTTP \(http.statusCode)")
        }
        return try Self.toolReply(from: data)
    }

    /// The tool's reply out of a JSON-RPC response body.
    static func toolReply(from data: Data) throws -> TideToolReply {
        let reply: TideRPCReply
        do {
            reply = try JSONDecoder().decode(TideRPCReply.self, from: data)
        } catch {
            throw TideTransportError.unexpectedReply("Reply wasn't JSON-RPC")
        }
        if let failure = reply.error {
            throw TideTransportError.unexpectedReply("JSON-RPC error \(failure.code): \(failure.message)")
        }
        guard let result = reply.result?.objectValue else {
            throw TideTransportError.unexpectedReply("Reply had no result")
        }
        let parts = result["content"]?.arrayValue ?? []
        let text = parts.compactMap { $0.objectValue?["text"]?.stringValue }.joined(separator: "\n")
        return TideToolReply(text: text, isError: result["isError"]?.boolValue ?? false)
    }

    private static func transportError(for error: URLError) -> TideTransportError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .resourceUnavailable:
            return .notRunning
        default:
            return .unexpectedReply("URLError \(error.code.rawValue)")
        }
    }
}

// MARK: - JSON-RPC, the client's half

/// One JSON-RPC request as a client sends it, in the notebook's own message
/// types (`JSONRPCID`, `JSONValue`; its MCP server only ever decodes requests).
struct TideRPCCall: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCID
    let method: String
    let params: JSONValue

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

/// A JSON-RPC response as a client reads one.
struct TideRPCReply: Decodable {
    let id: JSONRPCID?
    let result: JSONValue?
    let error: Failure?

    struct Failure: Decodable {
        let code: Int
        let message: String
    }
}
