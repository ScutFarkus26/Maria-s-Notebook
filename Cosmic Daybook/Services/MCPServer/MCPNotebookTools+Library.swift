//
//  MCPNotebookTools+Library.swift
//  Cosmic Daybook
//
//  The day pad: the teacher's one note for a day. The file once also held the
//  resource library (list_resources, taken out with Resources on 2026-11-22)
//  and the book club (taken out on 2026-11-21).
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Day Pad

    static func dayPadTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "day_pad",
            title: "Day Pad",
            description: "The teacher's note for a day — whatever they jotted down that did not "
                + "belong anywhere else. It is the one day note the Calendar shows (it no longer "
                + "appears on Today). Reads one day, or writes/replaces it.",
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
