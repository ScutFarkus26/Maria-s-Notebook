//
//  MCPNotebookTools+WriteJournal.swift
//  Cosmic Daybook
//
//  Reading back what was written over MCP.
//
//  The write tools cite what they touched, but only in the reply to the call
//  that made it — once a session ends those ids are gone, and a record filed
//  over MCP looks exactly like one the guide typed in the app. `MCPWriteJournal`
//  keeps them; this tool is how they are read. It is the surface a guide (or
//  the model) uses to check an afternoon of filing, and the ids it prints are
//  the ones the update_* tools take, so a mistake can be walked back.
//

import Foundation

extension MCPNotebookTools {

    static func recentMCPWritesTool(journal: MCPWriteJournal) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "recent_mcp_writes",
            title: "Recent MCP Writes",
            description: "Every record these tools created or changed on this Mac, newest first, "
                + "with the ids the update_* tools accept and the arguments each call was made "
                + "with. Use it to review a filing session, or to find what to undo after one.",
            inputSchema: recentWritesSchema,
            annotations: .readOnly,
            handler: { arguments in
                let request = try WriteJournalRequest(arguments)
                let records = await journal.records(
                    since: request.since, until: request.window.endExclusive,
                    tool: request.tool, limit: request.limit
                )
                return describeWrites(records, request: request)
            }
        )
    }

    private static var recentWritesSchema: JSONValue {
        var properties: [String: JSONValue] = [
            "days": [
                "type": "integer",
                "description": "How many days back to look, 1-365 (default 7). Ignored when since is given."
            ],
            "tool": [
                "type": "string",
                "description": "Only calls to this exact tool name, e.g. record_presentation"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum records to return, 1-500 (default 50)"
            ]
        ]
        properties.merge(dayWindowSchema("writes made")) { current, _ in current }
        return ["type": "object", "properties": .object(properties)]
    }

    /// The parsed arguments, so the handler and the header agree on the window.
    struct WriteJournalRequest {
        let days: Int
        let window: DayWindow
        let tool: String?
        let limit: Int
        /// `since` replaces the rolling window; without it, `days` back.
        let since: Date?

        init(_ arguments: [String: JSONValue]) throws {
            days = intArgument(arguments, "days", default: 7, range: 1...365)
            window = try dayWindowArgument(arguments)
            tool = nonEmpty(arguments["tool"]?.stringValue)
            limit = intArgument(arguments, "limit", default: 50, range: 1...500)
            since = window.start ?? AppCalendar.shared.date(
                byAdding: .day, value: -days, to: AppCalendar.startOfDay(Date())
            )
        }
    }

    private static func describeWrites(
        _ records: [MCPWriteRecord], request: WriteJournalRequest
    ) -> String {
        guard !records.isEmpty else {
            return "Nothing has been written over MCP in that window."
        }
        let scope = request.tool.map { " by \($0)" } ?? ""
        let when = request.window.isSet ? request.window.phrase : " in the last \(request.days) days"
        var lines: [String] = ["\(records.count) write(s) over MCP\(scope)\(when):"]
        for record in records {
            lines.append(headline(record))
            lines.append("    args: \(record.arguments)")
        }
        return lines.joined(separator: "\n")
    }

    private static func headline(_ record: MCPWriteRecord) -> String {
        let stamp = "\(dayString(record.timestamp)) \(timeString(record.timestamp))"
        let tag = record.destructive ? " (destructive)" : ""
        return "- \(stamp) \(record.tool)\(tag) → \(oneLine(record.receipt))"
    }

    /// Receipts are multi-line for the batch tools; the journal prints one
    /// line per record, so the rest folds in behind a separator.
    private static func oneLine(_ text: String) -> String {
        let parts = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "(no receipt)" : parts.joined(separator: " · ")
    }
}
