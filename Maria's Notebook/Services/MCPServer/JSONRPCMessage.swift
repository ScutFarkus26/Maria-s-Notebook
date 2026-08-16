//
//  JSONRPCMessage.swift
//  Maria's Notebook
//
//  JSON-RPC 2.0 message types for the MCP server transport.
//  Messages are newline-delimited UTF-8 JSON, per the MCP stdio transport
//  specification (2025-06-18). Batching was removed from that revision,
//  so exactly one message is decoded per line.
//

import Foundation

/// A JSON-RPC 2.0 request or notification received from an MCP client.
/// Notifications carry no `id` and never receive a response.
struct JSONRPCRequest: Decodable, Sendable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?

    var isNotification: Bool { id == nil }
}

/// A JSON-RPC request identifier: a string or a number.
enum JSONRPCID: Codable, Sendable, Equatable {
    case number(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON-RPC id must be a string or number"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

/// A JSON-RPC 2.0 response sent back to an MCP client.
struct JSONRPCResponse: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id: JSONRPCID?
    var result: JSONValue?
    var error: JSONRPCErrorPayload?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        // A response to a parse failure has an explicit null id.
        if let id {
            try container.encode(id, forKey: .id)
        } else {
            try container.encodeNil(forKey: .id)
        }
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }

    static func success(id: JSONRPCID?, result: JSONValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result, error: nil)
    }

    static func failure(id: JSONRPCID?, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: nil, error: JSONRPCErrorPayload(code: code, message: message))
    }
}

/// The `error` member of a failed JSON-RPC response.
struct JSONRPCErrorPayload: Encodable, Sendable {
    let code: Int
    let message: String
}

/// Standard JSON-RPC 2.0 error codes used by the MCP server.
enum JSONRPCErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}
