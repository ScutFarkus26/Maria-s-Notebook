//
//  MCPNotebookTools+Supplies.swift
//  Maria's Notebook
//
//  The supply shelf: what is there and what was used.
//
//  Every quantity change writes a CDSupplyTransaction alongside the new count,
//  the way the supply screen does — the running total and its history must not
//  drift apart, or "where did the beads go" becomes unanswerable.
//
//  The Supply entity carries minimumThreshold / unit / isOnOrder columns in the
//  Core Data model, but nothing in the app declares or writes them, so there is
//  no reorder threshold to report. `below` lets the caller supply one instead.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Reading the Shelf

    static func listSuppliesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_supplies",
            title: "List Supplies",
            description: "The supply inventory: what is on the shelf, how much of it, and "
                + "where it lives. The app keeps no reorder threshold, so pass `below` to ask "
                + "what has fallen under a number.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "below": [
                        "type": "integer",
                        "description": "Only supplies with fewer than this many on hand"
                    ],
                    "out_of_stock_only": [
                        "type": "boolean",
                        "description": "Only supplies with none left (default false)"
                    ],
                    "category": [
                        "type": "string",
                        "description": "Only this category — Art, Math, Language, Science, Office, and so on"
                    ],
                    "search": [
                        "type": "string",
                        "description": "Match against name, location, or notes, as the supply list does"
                    ]
                ]
            ],
            handler: { arguments in
                describeSupplies(arguments: arguments, in: context())
            }
        )
    }

    private static func describeSupplies(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let outOnly = arguments["out_of_stock_only"]?.boolValue ?? false
        let below = arguments["below"]?.intValue
        let category = nonEmpty(arguments["category"]?.stringValue)?.lowercased()
        let search = nonEmpty(arguments["search"]?.stringValue)?.lowercased()

        let all: [CDSupply] = modelContext.safeFetch(CDFetchRequest(CDSupply.self))
        var kept: [CDSupply] = []
        for supply in all
        where keeps(supply, outOnly: outOnly, below: below, category: category, search: search) {
            kept.append(supply)
        }
        let matched: [CDSupply] = kept.sorted { lhs, rhs in
            let leftKey: String = lhs.category.rawValue
            let rightKey: String = rhs.category.rawValue
            if leftKey != rightKey { return leftKey < rightKey }
            return lhs.name < rhs.name
        }

        guard !matched.isEmpty else {
            if outOnly { return "Nothing is out of stock." }
            if let below { return "Nothing is below \(below)." }
            return "No supplies match that."
        }

        let lines = matched.map { supply -> String in
            let id = supply.id?.uuidString ?? "unknown"
            var details = ["\(supply.currentQuantity) on hand"]
            if let location = nonEmpty(supply.location) {
                details.append("in \(location)")
            }
            if let notes = nonEmpty(supply.notes) {
                details.append(notes)
            }
            return "- [supply id=\(id)] \(supply.name) (\(supply.category.rawValue)) — "
                + details.joined(separator: ", ")
        }
        return "\(matched.count) supply/supplies:\n" + lines.joined(separator: "\n")
    }

    private static func keeps(
        _ supply: CDSupply, outOnly: Bool, below: Int?, category: String?, search: String?
    ) -> Bool {
        let quantity: Int64 = supply.currentQuantity
        if outOnly && quantity > 0 { return false }
        if let below, quantity >= Int64(below) { return false }
        if let category, supply.category.rawValue.lowercased() != category { return false }
        if let search, !matchesSearch(supply, search) { return false }
        return true
    }

    /// Matches the supply list's own search: name, location, or notes.
    private static func matchesSearch(_ supply: CDSupply, _ needle: String) -> Bool {
        if supply.name.lowercased().contains(needle) { return true }
        if supply.location.lowercased().contains(needle) { return true }
        return supply.notes.lowercased().contains(needle)
    }

    // MARK: - Adjusting Stock

    static func adjustSupplyTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "adjust_supply",
            title: "Adjust Supply Count",
            description: "Record supplies used, received, or recounted. Pass `change` for a "
                + "relative move (-12 used, +50 delivered) or `set_to` for a fresh count after "
                + "checking the shelf. Either way the change is logged with its reason, so the "
                + "running total and the history agree.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "supply": [
                        "type": "string",
                        "description": "The supply's id or its exact name"
                    ],
                    "change": [
                        "type": "integer",
                        "description": "How much to add (positive) or take away (negative)"
                    ],
                    "set_to": [
                        "type": "integer",
                        "description": "The counted quantity now on the shelf"
                    ],
                    "reason": [
                        "type": "string",
                        "description": "Why it changed — used in a lesson, delivered, recounted"
                    ]
                ],
                "required": ["supply"]
            ],
            handler: { arguments in
                try adjustSupply(arguments: arguments, in: context())
            }
        )
    }

    private static func adjustSupply(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let supply = try resolveSupply(requireString(arguments, "supply"), in: modelContext)
        let change = arguments["change"]?.intValue
        let setTo = arguments["set_to"]?.intValue
        guard change != nil || setTo != nil else {
            throw MCPToolError("Pass change (a relative move) or set_to (a counted quantity).")
        }
        guard change == nil || setTo == nil else {
            throw MCPToolError("Pass change or set_to, not both.")
        }

        let before = supply.currentQuantity
        let delta = Int64(change ?? ((setTo ?? 0) - Int(before)))
        guard delta != 0 else {
            return "\(supply.name) is already at \(before) — nothing to record."
        }
        let after = before + delta
        guard after >= 0 else {
            throw MCPToolError(
                "That would leave \(supply.name) at \(after). Stock cannot go negative — "
                    + "there are \(before) on hand."
            )
        }

        supply.currentQuantity = after
        supply.modifiedAt = Date()

        let transaction = CDSupplyTransaction(context: modelContext)
        transaction.id = UUID()
        transaction.supplyID = supply.id?.uuidString ?? ""
        transaction.date = Date()
        transaction.quantityChange = delta
        transaction.reason = nonEmpty(arguments["reason"]?.stringValue) ?? "Adjusted"
        transaction.supply = supply

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The adjustment could not be saved.")
        }

        let id = supply.id?.uuidString ?? "unknown"
        let direction = delta > 0 ? "+\(delta)" : "\(delta)"
        let warning = after == 0 ? " That is the last of it." : ""
        return "[supply id=\(id)] \(supply.name): \(direction), now \(after) "
            + "(\(transaction.reason)).\(warning)"
    }

    private static func resolveSupply(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDSupply {
        let supplies = modelContext.safeFetch(CDFetchRequest(CDSupply.self))
        if let id = UUID(uuidString: reference) {
            guard let supply = supplies.first(where: { $0.id == id }) else {
                throw MCPToolError("No supply with id \(reference) was found.")
            }
            return supply
        }
        let token = reference.folding(options: .diacriticInsensitive, locale: .current)
            .trimmed().lowercased()
        let exact = supplies.filter {
            $0.name.folding(options: .diacriticInsensitive, locale: .current).lowercased() == token
        }
        if exact.count == 1, let supply = exact.first { return supply }
        if exact.count > 1 {
            throw MCPToolError("More than one supply is called \"\(reference)\".")
        }
        let partial = supplies.filter {
            $0.name.folding(options: .diacriticInsensitive, locale: .current)
                .lowercased().contains(token)
        }
        if partial.count == 1, let supply = partial.first { return supply }
        if partial.count > 1 {
            let names = partial.map(\.name).sorted().prefix(8).joined(separator: ", ")
            throw MCPToolError("\"\(reference)\" matches several supplies: \(names).")
        }
        throw MCPToolError("No supply called \"\(reference)\" was found.")
    }
}
