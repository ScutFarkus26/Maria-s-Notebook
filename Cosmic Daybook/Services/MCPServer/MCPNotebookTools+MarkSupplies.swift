//
//  MCPNotebookTools+MarkSupplies.swift
//  Cosmic Daybook
//
//  `mark_supplies`: set staples' levels, or work Restock's needs (add them, move
//  them between stages) — the writes behind the Restock page, through
//  RestockService. The need halves live in MCPNotebookTools+OrderWrites.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Marking Levels

    static func markSuppliesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_supplies",
            title: "Mark Supply Levels",
            description: "Set the level of one or more staples: stocked, low, or out. Low and out put "
                + "the staple on the office run or the to-order list (one open need each); stocked "
                + "takes it off again. Every name is checked before anything is saved, so one "
                + "unknown name changes nothing. A level a staple already has is reported, not "
                + "rewritten. Each change is logged in the staple's history. The same tool works "
                + "Restock's needs: new_needs adds some, needs moves them between stages or edits them "
                + "(see list_supplies with stage). Pass one of supplies, new_needs or needs per call.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "new_needs": newNeedsSchema,
                    "needs": needsSchema,
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
                ]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { try markSuppliesOrNeeds(arguments: arguments, in: $0) }
            }
        )
    }

    /// Levels, new needs or need moves: exactly one of the three per call, so a
    /// refusal in one part can't leave another part saved.
    private static func markSuppliesOrNeeds(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let given = ["supplies", "new_needs", "needs"].filter { arguments[$0]?.arrayValue?.isEmpty == false }
        guard given.count <= 1 else {
            throw MCPToolError("Pass only one of supplies, new_needs or needs in a call. Nothing was changed.")
        }
        switch given.first {
        case "new_needs": return try addOrderItems(arguments: arguments, in: modelContext)
        case "needs": return try updateOrderItems(arguments: arguments, in: modelContext)
        default: return try markSupplies(arguments: arguments, in: modelContext)
        }
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
}
