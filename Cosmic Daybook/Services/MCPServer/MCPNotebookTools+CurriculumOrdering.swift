//
//  MCPNotebookTools+CurriculumOrdering.swift
//  Cosmic Daybook
//
//  Re-sequencing a sub-area to match the album. The listed lessons take the
//  order given; any lesson in the sub-area the caller left out keeps its
//  relative order and follows them, so a partial list can never lose a
//  lesson. The write is the same one a drag in the scope map makes:
//  `orderInSequence` renumbered across the sub-area, `sortIndex` rebuilt
//  across the area, one save.
//
//  With `sub_areas` instead, it sets the order of the area's sub-areas — the
//  order the Class Grid, the Lessons map and find_lessons draw them in, the
//  same one the Class Grid's Move Up / Move Down saves (`SubAreaOrder`). It is
//  a synced preference, like a drag in the map, so the guide's other devices
//  follow it; nothing in the notebook changes.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func reorderLessonsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "reorder_lessons",
            title: "Reorder Lessons",
            description: "Set the sequence order of one sub-area (sub_area + lesson_ids), or the order "
                + "of an area's sub-areas (sub_areas). The lessons in lesson_ids take that order from the "
                + "top; any other lesson in the sub-area keeps its relative order and follows them, so "
                + "nothing is dropped. A lesson from another sub-area is refused — move it with "
                + "update_lesson first. A section has no order of its own: it sits where its earliest "
                + "lesson falls, so move its lessons to move it. sub_areas works the same way for the "
                + "area's sub-areas (\"Ungrouped\" places the lessons filed under none) and reaches the "
                + "guide's other devices through iCloud. Returns the full resulting order.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "area": ["type": "string", "description": "The lessons' area, e.g. \"Language\""],
                    "sub_area": [
                        "type": "string",
                        "description": "The sub-area whose lessons to reorder, e.g. \"Logical Analysis\""
                    ],
                    "lesson_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": .string("Lesson ids (from find_lessons) in "
                            + "the order they should run. May be a subset of the sub-area.")
                    ],
                    "sub_areas": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": .string("Instead of sub_area and lesson_ids: the area's sub-area "
                            + "names in the order the Class Grid and the map should show them. May be a "
                            + "subset; the rest keep their relative order and follow.")
                    ]
                ],
                "required": ["area"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { try reorderLessons(arguments: arguments, in: $0) }
            }
        )
    }

    private static func reorderLessons(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lessons = allCurriculumLessons(in: modelContext)
        let area = try resolveArea(try requireString(arguments, "area"), from: lessons)
        let subAreas = stringArrayArgument(arguments, "sub_areas")
        let references = stringArrayArgument(arguments, "lesson_ids")
        let subArea = nonEmpty(arguments["sub_area"]?.stringValue)
        if !subAreas.isEmpty {
            guard subArea == nil, references.isEmpty else {
                throw MCPToolError(
                    "Give either sub_areas (to order the area's sub-areas) or sub_area with lesson_ids "
                        + "(to order one sub-area's lessons), not both."
                )
            }
            return try reorderSubAreas(subAreas, inArea: area, from: lessons)
        }
        guard let subArea else {
            throw MCPToolError(
                "Give sub_area with lesson_ids to order one sub-area's lessons, or sub_areas to order "
                    + "the area's sub-areas."
            )
        }
        let sequence = try resolveSequence(subArea, inArea: area, from: lessons)
        guard !references.isEmpty else {
            throw MCPToolError("lesson_ids must list at least one lesson.")
        }

        let current = lessonsInSequence(sequence, area: area, from: lessons)
        let label = filingLabel(area: area, sequence: sequence)
        // The table read above answers every reference; nothing is written until they all resolve.
        let resolver = LessonReferences(in: modelContext, table: lessons)
        var listed: [CDLesson] = []
        for reference in references {
            let lesson = try resolver.resolve(reference)
            guard current.contains(lesson) else {
                throw MCPToolError(
                    "\(describeLesson(lesson)) is not in \(label). Move it there with update_lesson "
                        + "first, or leave it out of lesson_ids."
                )
            }
            guard !listed.contains(lesson) else {
                throw MCPToolError("\(describeLesson(lesson)) appears more than once in lesson_ids.")
            }
            listed.append(lesson)
        }

        let ordered = listed + current.filter { !listed.contains($0) }
        renumberSequence(ordered)
        rebuildSortIndex(forArea: area, from: lessons)
        guard modelContext.safeSave() else {
            throw MCPToolError("The new order could not be saved.")
        }

        let carried = ordered.count - listed.count
        let note = carried > 0 ? " (\(carried) unlisted lesson(s) kept their order after them)" : ""
        return "\(label) now runs\(note):\n" + numberedLessonLines(ordered)
    }

    /// The area's sub-areas in a new order: the listed ones from the top, the rest
    /// after them in the order they had. Saved where the Class Grid's Move Up /
    /// Move Down saves it, so nothing in the notebook is written.
    private static func reorderSubAreas(
        _ references: [String], inArea area: String, from lessons: [CDLesson]
    ) throws -> String {
        let current = orderedSequences(inArea: area, from: lessons)
        var listed: [String] = []
        for reference in references {
            let sequence = try resolveSequence(reference, inArea: area, from: lessons)
            guard !listed.contains(where: { sameFiling($0, sequence) }) else {
                throw MCPToolError("\(sequence) appears more than once in sub_areas.")
            }
            listed.append(sequence)
        }
        let ordered = listed + current.filter { sequence in !listed.contains { sameFiling($0, sequence) } }
        SubAreaOrder.save(ordered, area: area)

        let carried = ordered.count - listed.count
        let note = carried > 0 ? " (\(carried) unlisted sub-area(s) kept their order after them)" : ""
        let lines = ordered.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return "\(area)'s sub-areas now run\(note):\n" + lines.joined(separator: "\n")
            + "\nThe Class Grid, the Lessons map and find_lessons show them in this order; the guide's "
            + "other devices follow once iCloud passes it on."
    }
}
