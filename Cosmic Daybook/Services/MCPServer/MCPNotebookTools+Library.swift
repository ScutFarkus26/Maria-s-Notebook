//
//  MCPNotebookTools+Library.swift
//  Cosmic Daybook
//
//  The shelves either side of the teaching albums: the resource library
//  (printables, charts, forms) and the book club (packets, sessions, the
//  meetings inside them).
//
//  Both features store their PDFs outside Core Data — as security-scoped
//  bookmarks or relative paths — so these tools return what a guide needs to
//  find a file, never the file itself.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Resource Library

    static func listResourcesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_resources",
            title: "List Resources",
            description: "The resource library: printables, charts, forms and guides the teacher "
                + "keeps on file, with their category, tags and size. The files themselves stay "
                + "on disk — this reports what exists and where it is filed.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "search": [
                        "type": "string",
                        "description": "Match against title, description, or tags"
                    ],
                    "category": [
                        "type": "string",
                        "description": "Only this category — Writing Papers, Math, Forms & Templates, and so on"
                    ],
                    "favorites_only": [
                        "type": "boolean",
                        "description": "Only resources marked favourite (default false)"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum resources to return, 1-100 (default 40)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeResources(arguments: arguments, in: context())
            }
        )
    }

    private static func describeResources(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let search: String? = nonEmpty(arguments["search"]?.stringValue)?.lowercased()
        let category: String? = nonEmpty(arguments["category"]?.stringValue)?.lowercased()
        let favouritesOnly: Bool = arguments["favorites_only"]?.boolValue ?? false
        let limit: Int = intArgument(arguments, "limit", default: 40, range: 1...100)

        // Folded by id: a resource cloned between the private and shared stores
        // carries the same id in both, and an unscoped fetch legitimately sees
        // both. See `describeSupplies` for the whole story.
        let all: [CDResource] = modelContext.safeFetch(CDFetchRequest(CDResource.self)).uniqueByID
        var kept: [CDResource] = []
        for resource in all {
            if favouritesOnly && !resource.isFavorite { continue }
            if let category, resource.category.rawValue.lowercased() != category { continue }
            if let search, !resourceMatches(resource, search) { continue }
            kept.append(resource)
        }
        guard !kept.isEmpty else { return "No resources match that." }

        let sorted: [CDResource] = kept.sorted { lhs, rhs in
            let leftKey: String = lhs.category.rawValue
            let rightKey: String = rhs.category.rawValue
            if leftKey != rightKey { return leftKey < rightKey }
            return lhs.title < rhs.title
        }
        let shown: [CDResource] = Array(sorted.prefix(limit))
        let lines = shown.map { resource -> String in
            let id: String = resource.id?.uuidString ?? "unknown"
            var details: [String] = [resource.category.rawValue]
            if resource.isFavorite {
                details.append("favourite")
            }
            let tags: [String] = resource.tagsArray
            if !tags.isEmpty {
                details.append(tags.joined(separator: ", "))
            }
            if resource.fileSizeBytes > 0 {
                details.append(resource.fileSizeFormatted)
            }
            let summary: String = nonEmpty(resource.descriptionText).map { "\n    \($0)" } ?? ""
            return "- [resource id=\(id)] \(resource.title) (\(details.joined(separator: "; ")))\(summary)"
        }
        let more: String = sorted.count > shown.count
            ? "\n(\(sorted.count - shown.count) more not shown.)"
            : ""
        return "\(sorted.count) resource(s):\n" + lines.joined(separator: "\n") + more
    }

    private static func resourceMatches(_ resource: CDResource, _ needle: String) -> Bool {
        if resource.title.lowercased().contains(needle) { return true }
        if resource.descriptionText.lowercased().contains(needle) { return true }
        for tag in resource.tagsArray where tag.lowercased().contains(needle) {
            return true
        }
        return false
    }

    // MARK: - Day Pad

    static func dayPadTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "day_pad",
            title: "Day Pad",
            description: "The teacher's note for a day — whatever they jotted down that did not "
                + "belong anywhere else. It is the one day note: Today's Pad and the Calendar show "
                + "the same text. Reads one day, or writes/replaces it.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "The day, YYYY-MM-DD (default today)"
                    ],
                    "body": [
                        "type": "string",
                        "description": .string("New text for that day. Replaces what is there — "
                            + "read it first if you mean to add to it. Omit to just read.")
                    ]
                ]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try dayPad(arguments: arguments, in: context())
            }
        )
    }

    private static func dayPad(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let day: Date = AppCalendar.startOfDay(try dayArgument(arguments, "date") ?? Date())
        // A scope of its own rather than `undoingOnFailure`: a read whose join
        // can't be saved takes the join back and still answers.
        let scope = MCPWriteScope(context: modelContext)
        // The app's own fetch: two devices' copies of the day are joined into the
        // one every device keeps, rather than reading or overwriting whichever
        // copy the store returned first.
        let existing: CDDayPad? = TodayDataFetcher.fetchDayPad(day: day, context: modelContext)

        guard let body = arguments["body"]?.stringValue else {
            if modelContext.deletedObjects.contains(where: { $0 is CDDayPad }), !modelContext.safeSave() {
                scope.undo()
            } else {
                scope.commit()
            }
            guard let text = existing.flatMap({ nonEmpty($0.body) }) else {
                return "The pad for \(dayString(day)) is empty."
            }
            return "Day pad for \(dayString(day)):\n\(text)"
        }

        let pad: CDDayPad = existing ?? {
            let created = CDDayPad(context: modelContext)
            created.id = UUID()
            created.day = day
            created.createdAt = Date()
            return created
        }()
        pad.body = body
        pad.modifiedAt = Date()

        guard modelContext.safeSave() else {
            scope.undo()
            throw MCPToolError("The day pad could not be saved.")
        }
        scope.commit()
        let verb: String = existing == nil ? "Wrote" : "Replaced"
        return "\(verb) the day pad for \(dayString(day))."
    }
}
