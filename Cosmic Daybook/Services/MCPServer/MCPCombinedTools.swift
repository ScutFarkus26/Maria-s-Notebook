//
//  MCPCombinedTools.swift
//  Cosmic Daybook
//
//  One read tool standing in for several that answer questions about the same
//  subject. The caller picks which with `view`; every other argument is passed
//  on to that view's own handler, so each view behaves exactly as the tool it
//  replaced did. The catalogue is sent to Claude on every connection, so a
//  subject that took five tools (and five descriptions, schemas and titles)
//  takes one.
//
//  Calling an old name still answers: `MCPNotebookTools.retiredTools` says
//  which tool and `view` it moved to.
//

import Foundation

extension MCPNotebookTools {

    /// A read tool made of the given views. Every view must be read-only.
    /// `defaultView` is what a call without `view` gets; without one, `view`
    /// is required.
    static func combinedReadTool(
        name: String, title: String, intro: String, defaultView: String? = nil,
        views: [(name: String, tool: MCPToolDefinition)]
    ) -> MCPToolDefinition {
        assert(views.allSatisfy { $0.tool.annotations == .readOnly }, "\(name) combines reads only")
        let names = views.map(\.name)

        let description = ([intro] + views.map { "view \($0.name): \($0.tool.description)" })
            .joined(separator: "\n\n")
        var schema: JSONValue = [
            "type": "object",
            "properties": .object(combinedProperties(views: views, defaultView: defaultView))
        ]
        if defaultView == nil, case .object(var fields) = schema {
            fields["required"] = ["view"]
            schema = .object(fields)
        }

        return MCPToolDefinition(
            name: name,
            title: title,
            description: description,
            inputSchema: schema,
            annotations: .readOnly,
            handler: { arguments in
                let chosen = arguments["view"]?.stringValue?.trimmed().lowercased() ?? defaultView
                guard let chosen, let view = views.first(where: { $0.name == chosen }) else {
                    throw MCPToolError("Pass view: one of \(names.joined(separator: ", ")).")
                }
                return try await view.tool.handler(arguments)
            }
        )
    }

    /// The union of the views' properties plus `view`. A property more than one view reads keeps the first
    /// view's schema and gets every view's wording, each headed by its view.
    private static func combinedProperties(
        views: [(name: String, tool: MCPToolDefinition)], defaultView: String?
    ) -> [String: JSONValue] {
        var order: [String] = []
        var schemas: [String: JSONValue] = [:]
        var wording: [String: [String]] = [:]
        var needs: [String] = []
        for (view, tool) in views {
            let fields = tool.inputSchema.objectValue ?? [:]
            let required = (fields["required"]?.arrayValue ?? []).compactMap(\.stringValue)
            needs.append(required.isEmpty ? view : "\(view) (needs \(required.joined(separator: ", ")))")
            for (key, property) in (fields["properties"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                if schemas[key] == nil {
                    order.append(key)
                    schemas[key] = property
                }
                if let text = property.objectValue?["description"]?.stringValue {
                    wording[key, default: []].append("\(view): \(text)")
                }
            }
        }

        var properties: [String: JSONValue] = [:]
        for key in order {
            guard case .object(var property) = schemas[key] else { continue }
            if let lines = wording[key] {
                property["description"] = .string(lines.joined(separator: " "))
            }
            properties[key] = .object(property)
        }
        let fallback = defaultView.map { " Omitted, it is \($0)." } ?? ""
        properties["view"] = [
            "type": "string",
            "enum": .array(views.map { .string($0.name) }),
            "description": .string("Which view: \(needs.joined(separator: "; ")).\(fallback)")
        ]
        return properties
    }
}
