//
//  MCPNotebookTools+Orders.swift
//  Cosmic Daybook
//
//  The Orders list: links the guide wants the office to order, and where
//  each one stands — to request, asked for, confirmed, received.
//
//  The stage is read off the item's dates exactly as the Orders screen reads
//  it (`CDOrderItem.stage`), so the two can never disagree.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// The stage names tools accept and print, mapped to the app's stages.
    static let orderStageNames: [(name: String, stage: OrderStage)] = [
        ("to_request", .toRequest),
        ("asked_for", .requested),
        ("confirmed", .confirmed),
        ("received", .received)
    ]

    static func orderStageName(_ stage: OrderStage) -> String {
        orderStageNames.first { $0.stage == stage }?.name ?? stage.rawValue
    }

    // MARK: - Reading the List

    static func listOrdersTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_orders",
            title: "List Orders",
            description: "The Orders list: links the guide wants the office to order, grouped by "
                + "stage — to_request (not asked for yet), asked_for (in a request the office "
                + "hasn't confirmed), confirmed, received. Also says who requests go to.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "stage": [
                        "type": "string",
                        "enum": ["open", "to_request", "asked_for", "confirmed", "received", "all"],
                        "description": .string("Which items: open (default — everything not yet "
                            + "received), one stage, or all")
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeOrders(arguments: arguments, in: context())
            }
        )
    }

    private static func describeOrders(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let filter = nonEmpty(arguments["stage"]?.stringValue)?.lowercased() ?? "open"
        let stages: [OrderStage]
        switch filter {
        case "open": stages = [.toRequest, .requested, .confirmed]
        case "all": stages = OrderStage.allCases
        default:
            guard let match = orderStageNames.first(where: { $0.name == filter }) else {
                throw MCPToolError(
                    "Unknown stage \"\(filter)\". Use open, to_request, asked_for, confirmed, received, or all."
                )
            }
            stages = [match.stage]
        }

        let request = CDFetchRequest(CDOrderItem.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDOrderItem.createdAt, ascending: true)]
        let items = modelContext.safeFetch(request)

        var sections: [String] = [recipientLine()]
        for stage in stages {
            let members = items.filter { $0.stage == stage }
            guard !members.isEmpty else { continue }
            let lines = members.map(orderLine)
            sections.append("\(orderStageName(stage)) (\(members.count)):\n" + lines.joined(separator: "\n"))
        }
        guard sections.count > 1 else {
            return sections[0] + "\nNo orders " + (filter == "all" ? "yet." : "match that.")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func recipientLine() -> String {
        let recipient = OrderRequestRecipient.stored()
        guard recipient.isConfigured else {
            return "Requests go to: not set (Settings › Communication › Order Requests)."
        }
        let name = recipient.name.isEmpty ? "" : "\(recipient.name) "
        return "Requests go to: \(name)<\(recipient.email)>."
    }

    static func orderLine(_ item: CDOrderItem) -> String {
        let id = item.id?.uuidString ?? "unknown"
        var details: [String] = []
        if item.quantity > 1 { details.append("qty \(item.quantity)") }
        if let url = nonEmpty(item.urlString) { details.append(url) }
        if let notes = nonEmpty(item.notes) { details.append("note: \(notes)") }
        if let asked = item.requestedAt {
            let from = nonEmpty(item.requestedFrom).map { " from \($0)" } ?? ""
            details.append("asked \(dayString(asked))\(from)")
        }
        if let confirmed = item.confirmedAt { details.append("confirmed \(dayString(confirmed))") }
        if let received = item.receivedAt { details.append("received \(dayString(received))") }
        return "- [order id=\(id)] \(item.displayTitle) — " + details.joined(separator: ", ")
    }
}
