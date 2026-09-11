//
//  MCPNotebookTools+CurriculumReads.swift
//  Maria's Notebook
//
//  Reading a whole area or sub-area of the curriculum in taught order, with
//  no cap. `find_lessons` stops at 25 because it answers "which lesson does
//  the guide mean"; this answers "what is in the notebook", which is what an
//  album-versus-notebook comparison needs in one call.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func listLessonsByAreaTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_lessons_by_area",
            title: "List Lessons By Area",
            description: "Every lesson in one area, or one sub-area, of the curriculum in sequence "
                + "order with no result cap — use it to compare the notebook against an album "
                + "before create_lesson or reorder_lessons. Lines are numbered by position within "
                + "their sub-area (1-based) and cite each lesson as [lesson id=<uuid>], the same id "
                + "find_lessons returns. An area listing groups by sub-area in the order the "
                + "scope map shows them.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "area": [
                        "type": "string",
                        "description": "The top-level area, e.g. \"Language\" or \"Math\""
                    ],
                    "sub_area": [
                        "type": "string",
                        "description": .string("One sub-area (sequence) within the area, e.g. "
                            + "\"Logical Analysis\". Omit for the whole area.")
                    ]
                ],
                "required": ["area"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try listLessonsByArea(arguments: arguments, in: context())
            }
        )
    }

    private static func listLessonsByArea(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lessons = allCurriculumLessons(in: modelContext)
        let area = try resolveArea(try requireString(arguments, "area"), from: lessons)

        if let subArea = nonEmpty(arguments["sub_area"]?.stringValue) {
            let sequence = try resolveSequence(subArea, inArea: area, from: lessons)
            let inSequence = lessonsInSequence(sequence, area: area, from: lessons)
            return sequenceBlock(sequence, area: area, lessons: inSequence)
        }

        let blocks = orderedSequences(inArea: area, from: lessons).map { sequence in
            sequenceBlock(sequence, area: area, lessons: lessonsInSequence(sequence, area: area, from: lessons))
        }
        let total = blocks.isEmpty ? 0 : lessons.filter { sameFiling($0.area, area) }.count
        return "\(area): \(total) lesson(s) in \(blocks.count) sub-area(s)\n\n" + blocks.joined(separator: "\n\n")
    }

    private static func sequenceBlock(_ sequence: String, area: String, lessons: [CDLesson]) -> String {
        let label = sequence == ungroupedSequenceLabel
            ? filingLabel(area: area, sequence: "")
            : filingLabel(area: area, sequence: sequence)
        return "\(label) — \(lessons.count) lesson(s)\n" + numberedLessonLines(lessons)
    }
}
