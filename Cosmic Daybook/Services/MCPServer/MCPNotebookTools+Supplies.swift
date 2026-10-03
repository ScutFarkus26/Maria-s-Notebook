//
//  MCPNotebookTools+Supplies.swift
//  Cosmic Daybook
//
//  The Restock shelf: each staple's level (Stocked, Low, Out), where it lives
//  and where it comes from, and the counts that are still kept.
//
//  Every write goes through RestockService, the one writer the notebook's page,
//  the Assistant and Siri use. A level change writes its own history line and
//  opens or closes the staple's need; a count change (`adjust_supply`) moves no
//  level, and writes a history line only when it is given a reason.
//
//  The Supply entity's minimumThreshold column is declared but unused (counted
//  staples are deferred), so there is no reorder threshold to report. `below`
//  lets the caller supply a count instead.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Reading the Shelf

    static func listSuppliesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_supplies",
            title: "List Supplies",
            description: "The Restock staples: each one's level (stocked, low, out), the place it "
                + "lives, whether it comes from the office or is ordered, and who set the level and "
                + "when. Low and out staples are what the office run and the to-order list are made "
                + "of (see list_orders). Counts are kept only where someone recorded one; pass "
                + "`below` to ask what has fallen under a number.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "below": [
                        "type": "integer",
                        "description": "Only supplies with fewer than this many on hand"
                    ],
                    "out_of_stock_only": [
                        "type": "boolean",
                        "description": "Only staples whose level is out (default false)"
                    ],
                    "level": [
                        "type": "string",
                        "enum": ["stocked", "low", "out", "needed"],
                        "description": "Only this level; needed means low or out"
                    ],
                    "source": [
                        "type": "string",
                        "enum": ["office", "order"],
                        "description": "Only staples fetched from the office, or ordered"
                    ],
                    "category": [
                        "type": "string",
                        "description": "Only this category (old data; the page now groups by place)"
                    ],
                    "search": [
                        "type": "string",
                        "description": "Match against name, place, or notes"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeSupplies(arguments: arguments, in: context())
            }
        )
    }

    private static func describeSupplies(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let filter = SupplyFilter(
            outOnly: arguments["out_of_stock_only"]?.boolValue ?? false,
            below: arguments["below"]?.intValue,
            level: try supplyLevelFilter(arguments["level"]?.stringValue),
            source: try supplySourceFilter(arguments["source"]?.stringValue),
            category: nonEmpty(arguments["category"]?.stringValue)?.lowercased(),
            search: nonEmpty(arguments["search"]?.stringValue)?.lowercased()
        )

        // Classroom entities live in both store configurations, so an unscoped
        // fetch legitimately spans private and shared — and a shelf that was
        // cloned between them under one id comes back two or three times.
        // `deduplicateAllModels` folds those rows away at launch; until it has
        // run, fold them for the reader. Scoping the fetch instead would be
        // wrong: on an assistant device these rows live only in the shared store.
        let all: [CDSupply] = RestockService.staples(in: modelContext).uniqueByID
        let kept = all.filter { keeps($0, filter) }
        let author = RestockAuthor.current(in: modelContext)

        guard !kept.isEmpty else {
            if filter.outOnly { return "Nothing is out." }
            if let below = filter.below { return "Nothing is below \(below)." }
            return "No supplies match that."
        }

        // The page's own order: by place, then name.
        let lines = RestockService.shelf(kept).flatMap { group in
            group.staples.map { supplyLine($0, author: author) }
        }
        return "\(kept.count) supply/supplies:\n" + lines.joined(separator: "\n")
    }

    private struct SupplyFilter {
        let outOnly: Bool
        let below: Int?
        /// Nil for any; otherwise the levels to keep.
        let level: Set<RestockLevel>?
        let source: RestockSource?
        let category: String?
        let search: String?
    }

    private static func supplyLevelFilter(_ raw: String?) throws -> Set<RestockLevel>? {
        guard let raw = nonEmpty(raw)?.lowercased() else { return nil }
        if raw == "needed" { return [.low, .out] }
        guard let level = RestockLevel(rawValue: raw) else {
            throw MCPToolError("Unknown level \"\(raw)\". Use stocked, low, out, or needed.")
        }
        return [level]
    }

    private static func supplySourceFilter(_ raw: String?) throws -> RestockSource? {
        guard let raw = nonEmpty(raw)?.lowercased() else { return nil }
        guard let source = RestockSource(rawValue: raw) else {
            throw MCPToolError("Unknown source \"\(raw)\". Use office or order.")
        }
        return source
    }

    private static func supplyLine(_ supply: CDSupply, author: RestockAuthor) -> String {
        let id = supply.id?.uuidString ?? "unknown"
        var details = [supply.level.displayName.lowercased()]
        details.append(nonEmpty(supply.location).map { "in \($0)" } ?? "no place yet")
        details.append(supply.source == .office ? "from the office" : "ordered")
        if let url = nonEmpty(supply.urlString) { details.append(url) }
        if supply.currentQuantity > 0 { details.append("\(supply.currentQuantity) counted") }
        if let changed = supply.levelChangedAt {
            let who = author.reads(changedByID: supply.levelChangedByID, name: supply.levelChangedByName)
            details.append("level set \(dayString(changed)) by \(who)")
        }
        if let notes = nonEmpty(supply.notes) { details.append(notes) }
        return "- [supply id=\(id)] \(supply.name) — " + details.joined(separator: ", ")
    }

    private static func keeps(_ supply: CDSupply, _ filter: SupplyFilter) -> Bool {
        if filter.outOnly && supply.level != .out { return false }
        if let level = filter.level, !level.contains(supply.level) { return false }
        if let source = filter.source, supply.source != source { return false }
        if let below = filter.below, supply.currentQuantity >= Int64(below) { return false }
        if let category = filter.category, supply.category.rawValue.lowercased() != category { return false }
        if let search = filter.search, !matchesSearch(supply, search) { return false }
        return true
    }

    /// Matches the page's own search: name, place, or notes.
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
            description: "Record a count: supplies used, received, or recounted. Pass `change` for a "
                + "relative move (-12 used, +50 delivered) or `set_to` for a fresh count after "
                + "checking the shelf. A count never changes the staple's level (use mark_supplies "
                + "for that). Either way the change is logged with its reason, so the running "
                + "count and the history agree.",
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
            annotations: .write,
            handler: { arguments in
                try rollingBackOnFailure(context()) { try adjustSupply(arguments: arguments, in: $0) }
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

        let reason = nonEmpty(arguments["reason"]?.stringValue) ?? "Adjusted"
        RestockService.setCount(supply, to: Int(after), reason: reason, in: modelContext)

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The adjustment could not be saved.")
        }

        let id = supply.id?.uuidString ?? "unknown"
        let direction = delta > 0 ? "+\(delta)" : "\(delta)"
        let warning = after == 0 ? " That is the last of it." : ""
        return "[supply id=\(id)] \(supply.name): \(direction), now \(after) "
            + "(\(reason)).\(warning)"
    }

    // MARK: - Marking Levels

    static func markSuppliesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_supplies",
            title: "Mark Supply Levels",
            description: "Set the level of one or more staples: stocked, low, or out. Low and out put "
                + "the staple on the office run or the to-order list (one open need each); stocked "
                + "takes it off again. Every name is checked before anything is saved, so one "
                + "unknown name changes nothing. A level a staple already has is reported, not "
                + "rewritten. Each change is logged in the staple's history.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "supplies": [
                        "type": "array",
                        "description": "One entry per staple",
                        "items": [
                            "type": "object",
                            "properties": [
                                "supply": ["type": "string", "description": "The supply's id or its exact name"],
                                "level": ["type": "string", "enum": ["stocked", "low", "out"]]
                            ],
                            "required": ["supply", "level"]
                        ]
                    ]
                ],
                "required": ["supplies"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try rollingBackOnFailure(context()) { try markSupplies(arguments: arguments, in: $0) }
            }
        )
    }

    private static func markSupplies(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let entries = arguments["supplies"]?.arrayValue, !entries.isEmpty else {
            throw MCPToolError("Pass supplies: at least one { supply, level }.")
        }
        // Every name and level is resolved before the first write.
        let marks: [(supply: CDSupply, level: RestockLevel)] = try entries.enumerated().map { index, entry in
            let fields = entry.objectValue ?? [:]
            let reference = nonEmpty(fields["supply"]?.stringValue) ?? ""
            let rawLevel = nonEmpty(fields["level"]?.stringValue)?.lowercased() ?? ""
            guard let level = RestockLevel(rawValue: rawLevel) else {
                throw MCPToolError(
                    "Entry \(index + 1): \"\(rawLevel)\" is not a level. Use stocked, low, or out. "
                        + "Nothing was changed."
                )
            }
            do {
                return (try resolveSupply(reference, in: modelContext), level)
            } catch let error as MCPToolError {
                throw MCPToolError("Entry \(index + 1): \(error.message) Nothing was changed.")
            }
        }

        let author = RestockAuthor.current(in: modelContext)
        var lines: [String] = []
        var changed = false
        for (supply, level) in marks {
            let before = supply.level
            if RestockService.setLevel(supply, to: level, by: author, in: modelContext) {
                changed = true
                lines.append(markLine(supply, from: before, in: modelContext))
            } else {
                lines.append("[supply id=\(supply.id?.uuidString ?? "unknown")] \(supply.name): "
                    + "already \(level.displayName.lowercased()), nothing to record.")
            }
        }
        guard changed else {
            MCPCallOutcome.markNothingWritten()
            return lines.joined(separator: "\n")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The levels could not be saved.")
        }
        return "Marked \(lines.count):\n" + lines.joined(separator: "\n")
    }

    private static func markLine(
        _ supply: CDSupply, from before: RestockLevel, in modelContext: NSManagedObjectContext
    ) -> String {
        let id = supply.id?.uuidString ?? "unknown"
        var line = "[supply id=\(id)] \(supply.name): \(before.displayName.lowercased()) to "
            + "\(supply.level.displayName.lowercased())."
        if supply.level.isNeeded {
            line += supply.source == .office ? " On the office run." : " On the to-order list."
        } else {
            line += " Its need is closed."
        }
        return line
    }

    static func resolveSupply(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDSupply {
        // Folded by id for the same reason `describeSupplies` folds: before the
        // cleanup pass runs, two clones of one supply would otherwise read as
        // "more than one supply is called that" and refuse the adjustment.
        let supplies = modelContext.safeFetch(CDFetchRequest(CDSupply.self)).uniqueByID
        if let id = UUID(uuidString: reference) {
            guard let supply = supplies.first(where: { $0.id == id }) else {
                throw MCPToolError("No supply with id \(reference) was found.")
            }
            return supply
        }
        let token = reference.folded()
        let exact = supplies.filter {
            $0.name.folded() == token
        }
        if exact.count == 1, let supply = exact.first { return supply }
        if exact.count > 1 {
            throw MCPToolError("More than one supply is called \"\(reference)\".")
        }
        let partial = supplies.filter {
            $0.name.folded().contains(token)
        }
        if partial.count == 1, let supply = partial.first { return supply }
        if partial.count > 1 {
            let names = partial.map(\.name).sorted().prefix(8).joined(separator: ", ")
            throw MCPToolError("\"\(reference)\" matches several supplies: \(names).")
        }
        throw MCPToolError("No supply called \"\(reference)\" was found.")
    }
}
