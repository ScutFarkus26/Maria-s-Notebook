//
//  MCPNotebookTools+OrderWrites.swift
//  Cosmic Daybook
//
//  Adding to the Orders list and moving items through its stages, through
//  the same `OrderService` calls the Orders screen makes.
//
//  Two boundaries, matching the rest of the server: nothing here deletes an
//  item, and nothing sends email — marking items asked_for records that the
//  guide asked; drafting and sending the request stays in the app.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Adding Items

    static func addOrderItemsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "add_order_items",
            title: "Add Order Items",
            description: "Add links to the Orders list under to_request. A link already on the "
                + "list and not yet received is reported, not added twice. Every link is "
                + "checked before anything is saved.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "description": "One entry per thing to order",
                        "items": [
                            "type": "object",
                            "properties": [
                                "url": ["type": "string", "description": "The product page link"],
                                "title": ["type": "string", "description": "What it is"],
                                "quantity": ["type": "integer", "description": "How many (default 1)"],
                                "notes": ["type": "string", "description": "A note for the office — size, color"]
                            ],
                            "required": ["url"]
                        ]
                    ]
                ],
                "required": ["items"]
            ],
            annotations: .write,
            handler: { arguments in
                try addOrderItems(arguments: arguments, in: context())
            }
        )
    }

    private struct OrderItemRequest {
        let url: URL
        let title: String?
        let quantity: Int
        let notes: String
    }

    private static func addOrderItems(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let entries = arguments["items"]?.arrayValue, !entries.isEmpty else {
            throw MCPToolError("Pass items: at least one { url, title, quantity, notes }.")
        }
        let requests: [OrderItemRequest] = try entries.enumerated().map { index, entry in
            let fields = entry.objectValue ?? [:]
            let raw = nonEmpty(fields["url"]?.stringValue) ?? ""
            guard let url = OrderService.webURL(from: raw) else {
                throw MCPToolError("Item \(index + 1): \"\(raw)\" is not a web link. Nothing was added.")
            }
            let quantity = fields["quantity"]?.intValue ?? 1
            guard quantity >= 1 else {
                throw MCPToolError("Item \(index + 1): quantity must be at least 1. Nothing was added.")
            }
            return OrderItemRequest(
                url: url,
                title: nonEmpty(fields["title"]?.stringValue),
                quantity: quantity,
                notes: nonEmpty(fields["notes"]?.stringValue) ?? ""
            )
        }

        var added: [CDOrderItem] = []
        var skipped: [String] = []
        for request in requests {
            let created = OrderService.addLinks(
                [request.url],
                title: request.title,
                quantity: request.quantity,
                notes: request.notes,
                in: modelContext
            )
            if created.isEmpty {
                skipped.append(request.url.absoluteString)
            }
            added += created
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The items could not be saved.")
        }

        var lines: [String] = []
        if !added.isEmpty {
            lines.append("Added \(added.count) to_request:")
            lines += added.map(orderLine)
        }
        if !skipped.isEmpty {
            lines.append("Already on the list, not added: " + skipped.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Updating Items

    static func updateOrderItemsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_order_items",
            title: "Update Order Items",
            description: "Move Orders items between stages or edit them. stage asked_for records "
                + "that the guide asked the office (it sends nothing) and groups the items as one "
                + "request; confirmed means the office acknowledged; received checks an item off; "
                + "not_received unchecks it; to_request forgets the request. Setting a stage an "
                + "item is already at changes nothing. Every id is checked before anything is saved.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string", "description": "The order id from list_orders"],
                                "stage": [
                                    "type": "string",
                                    "enum": ["to_request", "asked_for", "confirmed", "received", "not_received"]
                                ],
                                "title": ["type": "string"],
                                "quantity": ["type": "integer"],
                                "notes": ["type": "string"]
                            ],
                            "required": ["id"]
                        ]
                    ]
                ],
                "required": ["items"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateOrderItems(arguments: arguments, in: context())
            }
        )
    }

    private static func updateOrderItems(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let entries = arguments["items"]?.arrayValue, !entries.isEmpty else {
            throw MCPToolError("Pass items: at least one { id, stage, title, quantity, notes }.")
        }
        let resolved = try entries.map { try resolveOrderEdit($0, in: modelContext) }

        // Items newly asked for in one call form one request, as they would
        // from one drafted message.
        let newlyAsked = resolved
            .filter { $0.fields["stage"]?.stringValue == "asked_for" && $0.item.stage == .toRequest }
            .map(\.item)
        if !newlyAsked.isEmpty {
            OrderService.markRequested(newlyAsked, from: OrderRequestRecipient.stored().label)
        }

        for (item, fields) in resolved {
            applyOrderEdits(fields, to: item)
            applyOrderStage(fields["stage"]?.stringValue, to: item)
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The changes could not be saved.")
        }
        return "Updated \(resolved.count):\n" + resolved.map { orderLine($0.item) }.joined(separator: "\n")
    }

    /// Checks one entry before anything is written, so a bad id or stage anywhere
    /// in the batch leaves every item untouched.
    private static func resolveOrderEdit(
        _ entry: JSONValue, in modelContext: NSManagedObjectContext
    ) throws -> (item: CDOrderItem, fields: [String: JSONValue]) {
        let allowedStages: Set<String> = ["to_request", "asked_for", "confirmed", "received", "not_received"]
        let fields = entry.objectValue ?? [:]
        let reference = nonEmpty(fields["id"]?.stringValue) ?? ""
        guard let id = UUID(uuidString: reference),
              let item = modelContext.object(CDOrderItem.self, id: id) else {
            throw MCPToolError("No order with id \(reference) was found. Nothing was changed.")
        }
        if let stage = fields["stage"]?.stringValue, !allowedStages.contains(stage) {
            throw MCPToolError("Unknown stage \"\(stage)\". Nothing was changed.")
        }
        if let quantity = fields["quantity"]?.intValue, quantity < 1 {
            throw MCPToolError("Quantity must be at least 1. Nothing was changed.")
        }
        return (item, fields)
    }

    /// Every stage but asked_for, which `updateOrderItems` applies to the whole
    /// batch at once so the items share one request.
    private static func applyOrderStage(_ stage: String?, to item: CDOrderItem) {
        switch stage {
        case "to_request" where item.stage != .toRequest:
            OrderService.moveBackToRequest([item])
        case "confirmed":
            OrderService.markConfirmed([item])
        case "received":
            OrderService.setReceived([item], true)
        case "not_received":
            OrderService.setReceived([item], false)
        default:
            break
        }
    }

    private static func applyOrderEdits(_ fields: [String: JSONValue], to item: CDOrderItem) {
        let title = fields["title"]?.stringValue
        let quantity = fields["quantity"]?.intValue
        let notes = fields["notes"]?.stringValue
        guard title != nil || quantity != nil || notes != nil else { return }
        OrderService.update(
            item,
            title: title ?? item.title,
            urlString: item.urlString,
            quantity: quantity ?? Int(item.quantity),
            notes: notes ?? item.notes
        )
    }
}
