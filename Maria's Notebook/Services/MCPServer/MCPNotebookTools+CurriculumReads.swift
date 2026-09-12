//
//  MCPNotebookTools+CurriculumReads.swift
//  Maria's Notebook
//
//  Reading a whole area or sub-area of the curriculum in taught order, with
//  no cap. `find_lessons` stops at 25 because it answers "which lesson does
//  the guide mean"; this answers "what is in the notebook", which is what an
//  album-versus-notebook comparison needs in one call.
//
//  Within a sub-area the lessons sit under their section headings, in the
//  same bands the scope map and the Checklist draw (`LessonSectionGrouping`),
//  because this is the only read that shows a lesson's `section` — without
//  it a section set over MCP could never be checked from outside the app.
//  Positions stay 1-based across the whole sub-area, so a number here is the
//  one reorder_lessons and create_lesson report.
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
                + "scope map shows them. Within a sub-area, lessons that carry a section sit "
                + "under a \"Section: <name>\" heading in the map's band order, with the rest "
                + "under \"No section\"; a sub-area with no sections is a plain numbered list.",
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

    /// One sub-area: a header line, then its lessons under their section
    /// headings. `lessons` arrive in taught order and keep those positions
    /// whichever band they land in. A sub-area with no sections prints the
    /// plain numbered list it always did.
    private static func sequenceBlock(_ sequence: String, area: String, lessons: [CDLesson]) -> String {
        let storedSequence: String = sequence == ungroupedSequenceLabel ? "" : sequence
        let header = "\(filingLabel(area: area, sequence: storedSequence)) — \(lessons.count) lesson(s)"
        let bands = LessonSectionGrouping.bands(for: lessons, area: area, sequence: storedSequence)
        guard bands.contains(where: { !$0.name.isEmpty }) else {
            return header + "\n" + numberedLessonLines(lessons)
        }
        let positions: [NSManagedObjectID: Int] = Dictionary(
            uniqueKeysWithValues: lessons.enumerated().map { ($0.element.objectID, $0.offset + 1) }
        )
        let blocks: [String] = bands.map { band in
            let heading: String = band.name.isEmpty ? "No section" : "Section: \(band.name)"
            let lines: [String] = band.lessons.map { lesson in
                "\(positions[lesson.objectID] ?? 0). \(describeLesson(lesson))"
            }
            return ([heading] + lines).joined(separator: "\n")
        }
        return header + "\n" + blocks.joined(separator: "\n")
    }
}
