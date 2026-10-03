//
//  MCPNotebookTools+OrderWrites.swift
//  Cosmic Daybook
//
//  Adding needs to Restock and moving them through their stages, through the
//  same `RestockService` (and the `OrderService` stage moves behind it) that
//  the notebook's page uses.
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
            description: "Add needs to Restock under to_request. An entry takes a product link, a "
                + "title, or both; with only a title it is something to fetch from the school "
                + "office, and `source` says office or order (a link means order unless told "
                + "otherwise). A need already waiting (the same link, or the same title from the "
                + "same source) is reported, not added twice. Every entry is checked before anything "
                + "is saved.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "description": "One entry per thing to order",
                        "items": [
                            "type": "object",
                            "properties": [
                                "url": ["type": "string", "description": "The product page link (optional with a title)"],
                                "title": ["type": "string", "description": "What it is; required without a link"],
                                "source": [
                                    "type": "string",
                                    "enum": ["office", "order"],
                                    "description": "Fetch from the office, or order it"
                                ],
                                "quantity": ["type": "integer", "description": "How many (default 1)"],
                                "notes": ["type": "string", "description": "A note for the office — size, color"]
                            ],
                        ]
                    ]
                ],
                "required": ["items"]
            ],
            annotations: .write,
            handler: { arguments in
                try rollingBackOnFailure(context()) { try addOrderItems(arguments: arguments, in: $0) }
            }
        )
    }

    private struct OrderItemRequest {
        let url: URL?
        let title: String
        let source: RestockSource?
        let quantity: Int
        let notes: String
    }

    private static func addOrderItems(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let entries = arguments["items"]?.arrayValue, !entries.isEmpty else {
            throw MCPToolError("Pass items: at least one { url or title, source, quantity, notes }.")
        }
        let requests: [OrderItemRequest] = try entries.enumerated().map { index, entry in
            try orderItemRequest(entry, number: index + 1)
        }

        let author = RestockAuthor.current(in: modelContext)
        var added: [CDOrderItem] = []
        var skipped: [String] = []
        for request in requests {
            guard let result = RestockService.addOneOff(
                title: request.title,
                link: request.url,
                quantity: request.quantity,
                source: request.source,
                note: request.notes,
                by: author,
                in: modelContext
            ) else { continue }
            if result.isNew {
                added.append(result.object)
            } else {
                skipped.append(request.url?.absoluteString ?? request.title)
            }
        }

        if added.isEmpty { MCPCallOutcome.markNothingWritten() }
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

    /// Checks one entry before anything is written.
    private static func orderItemRequest(_ entry: JSONValue, number: Int) throws -> OrderItemRequest {
        let fields = entry.objectValue ?? [:]
        let raw = nonEmpty(fields["url"]?.stringValue)
        let title = nonEmpty(fields["title"]?.stringValue) ?? ""
        var url: URL?
        if let raw {
            guard let parsed = OrderService.webURL(from: raw) else {
                throw MCPToolError("Item \(number): \"\(raw)\" is not a web link. Nothing was added.")
            }
            url = parsed
        } else if title.isEmpty {
            throw MCPToolError("Item \(number): give a link or a title. Nothing was added.")
        }
        var source: RestockSource?
        if let rawSource = nonEmpty(fields["source"]?.stringValue)?.lowercased() {
            guard let parsed = RestockSource(rawValue: rawSource) else {
                throw MCPToolError("Item \(number): source must be office or order. Nothing was added.")
            }
            source = parsed
        }
        let quantity = fields["quantity"]?.intValue ?? 1
        guard quantity >= 1 else {
            throw MCPToolError("Item \(number): quantity must be at least 1. Nothing was added.")
        }
        return OrderItemRequest(
            url: url,
            title: title,
            source: source,
            quantity: quantity,
            notes: nonEmpty(fields["notes"]?.stringValue) ?? ""
        )
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
                try rollingBackOnFailure(context()) { try updateOrderItems(arguments: arguments, in: $0) }
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
            RestockService.markRequested(newlyAsked, from: OrderRequestRecipient.stored().label)
        }

        let author = RestockAuthor.current(in: modelContext)
        for (item, fields) in resolved {
            applyOrderEdits(fields, to: item)
            applyOrderStage(fields["stage"]?.stringValue, to: item, by: author, in: modelContext)
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
        if fields["stage"]?.stringValue == "confirmed", item.requestedAt == nil {
            throw MCPToolError(
                "\"\(item.title)\" hasn't been asked for, so the office can't have confirmed it; "
                    + "set it to asked_for first. Nothing was changed."
            )
        }
        if item.source == .office, ["asked_for", "confirmed"].contains(fields["stage"]?.stringValue ?? "") {
            throw MCPToolError(
                "\"\(item.displayTitle)\" is from the office, so it is never asked for or confirmed: "
                    + "it goes from to_request straight to received. Nothing was changed."
            )
        }
        if let quantity = fields["quantity"]?.intValue, quantity < 1 {
            throw MCPToolError("Quantity must be at least 1. Nothing was changed.")
        }
        return (item, fields)
    }

    /// Every stage but asked_for, which `updateOrderItems` applies to the whole
    /// batch at once so the items share one request.
    private static func applyOrderStage(
        _ stage: String?, to item: CDOrderItem, by author: RestockAuthor, in modelContext: NSManagedObjectContext
    ) {
        switch stage {
        case "to_request" where item.stage != .toRequest:
            RestockService.moveBackToRequest([item], by: author, in: modelContext)
        case "confirmed":
            RestockService.markConfirmed([item])
        case "received":
            // Checking off also puts the need's staple back to Stocked.
            RestockService.checkOff(item, by: author, in: modelContext)
        case "not_received":
            RestockService.reopen([item], by: author, in: modelContext)
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
