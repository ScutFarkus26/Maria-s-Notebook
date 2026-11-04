import Foundation
@testable import CosmicDaybook

extension MCPToolDefinition {
    /// The same tool with `key` set on every call, so a test of one view or
    /// section (`view: "ready"`, `sections: ["work"]`) reads like a test of
    /// the single-purpose tool it was before the subject's tools were merged.
    /// An argument the call passes itself wins.
    func presetting(_ key: String, _ value: JSONValue) -> MCPToolDefinition {
        let inner = handler
        return MCPToolDefinition(
            name: name, title: title, description: description,
            inputSchema: inputSchema, annotations: annotations,
            handler: { arguments in
                var merged = arguments
                if merged[key] == nil { merged[key] = value }
                return try await inner(merged)
            }
        )
    }
}
