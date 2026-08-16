import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Request Handler")
struct MCPRequestHandlerTests {
    private static func makeHandler(tools: [MCPToolDefinition] = [echoTool]) -> MCPRequestHandler {
        MCPRequestHandler(serverVersion: "1.0-test", tools: tools)
    }

    private static let echoTool = MCPToolDefinition(
        name: "echo",
        title: "Echo",
        description: "Returns its message argument.",
        inputSchema: [
            "type": "object",
            "properties": ["message": ["type": "string"]],
            "required": ["message"]
        ],
        handler: { arguments in
            guard let message = arguments["message"]?.stringValue else {
                throw MCPToolError("Missing message")
            }
            return "echo: \(message)"
        }
    )

    private func response(for json: String, handler: MCPRequestHandler) async throws -> [String: Any] {
        let data = await handler.handle(line: Data(json.utf8))
        let unwrapped = try #require(data)
        let object = try JSONSerialization.jsonObject(with: unwrapped)
        return try #require(object as? [String: Any])
    }

    @Test("Initialize echoes a supported protocol version")
    func initializeEchoesSupportedVersion() async throws {
        let json = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "marias-notebook")
        #expect(serverInfo["version"] as? String == "1.0-test")
    }

    @Test("Initialize offers the newest version when the client's is unknown")
    func initializeFallsBackToNewestVersion() async throws {
        let json = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
    }

    @Test("Notifications receive no response")
    func notificationsAreSilent() async {
        let handler = Self.makeHandler()
        let data = await handler.handle(
            line: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        )
        #expect(data == nil)
    }

    @Test("Ping returns an empty result")
    func pingReturnsEmptyResult() async throws {
        let json = #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let result = try #require(response["result"] as? [String: Any])
        #expect(result.isEmpty)
        #expect(response["id"] as? Int == 7)
    }

    @Test("tools/list describes registered tools")
    func toolsListDescribesTools() async throws {
        let json = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let result = try #require(response["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "echo")
        let schema = try #require(tools[0]["inputSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
    }

    @Test("tools/call executes the handler")
    func toolsCallExecutesHandler() async throws {
        let json = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"message":"hi"}}}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == "echo: hi")
    }

    @Test("Tool errors become isError results, not protocol errors")
    func toolErrorsBecomeToolResults() async throws {
        let json = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{}}}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == "Missing message")
    }

    @Test("Unknown tools are a protocol error")
    func unknownToolIsProtocolError() async throws {
        let json = #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope"}}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let error = try #require(response["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32602)
    }

    @Test("Unknown methods are method-not-found errors")
    func unknownMethodIsError() async throws {
        let json = #"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#
        let response = try await response(for: json, handler: Self.makeHandler())
        let error = try #require(response["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    @Test("Malformed JSON is a parse error with a null id")
    func malformedJSONIsParseError() async throws {
        let response = try await response(for: "{not json", handler: Self.makeHandler())
        let error = try #require(response["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32700)
        #expect(response["id"] is NSNull)
    }
}
