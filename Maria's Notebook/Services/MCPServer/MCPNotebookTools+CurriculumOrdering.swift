//
//  MCPNotebookTools+CurriculumOrdering.swift
//  Maria's Notebook
//
//  Re-sequencing a sub-area to match the album. The listed lessons take the
//  order given; any lesson in the sub-area the caller left out keeps its
//  relative order and follows them, so a partial list can never lose a
//  lesson. The write is the same one a drag in the scope map makes:
//  `orderInSequence` renumbered across the sub-area, `sortIndex` rebuilt
//  across the area, one save.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func reorderLessonsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "reorder_lessons",
            title: "Reorder Lessons",
            description: "Set the sequence order of one sub-area. The lessons in lesson_ids take "
                + "that order from the top; any other lesson in the sub-area keeps its relative "
                + "order and follows them, so nothing is dropped. A lesson from another sub-area is "
                + "refused — move it with update_lesson first. Returns the full resulting order.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "area": ["type": "string", "description": "The lessons' area, e.g. \"Language\""],
                    "sub_area": ["type": "string", "description": "The sub-area to reorder, e.g. \"Logical Analysis\""],
                    "lesson_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": .string("Lesson ids (from find_lessons or list_lessons_by_area) in "
                            + "the order they should run. May be a subset of the sub-area.")
                    ]
                ],
                "required": ["area", "sub_area", "lesson_ids"]
            ],
            handler: { arguments in
                try reorderLessons(arguments: arguments, in: context())
            }
        )
    }

    private static func reorderLessons(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lessons = allCurriculumLessons(in: modelContext)
        let area = try resolveArea(try requireString(arguments, "area"), from: lessons)
        let sequence = try resolveSequence(try requireString(arguments, "sub_area"), inArea: area, from: lessons)
        let references = stringArrayArgument(arguments, "lesson_ids")
        guard !references.isEmpty else {
            throw MCPToolError("lesson_ids must list at least one lesson.")
        }

        let current = lessonsInSequence(sequence, area: area, from: lessons)
        let label = filingLabel(area: area, sequence: sequence)
        var listed: [CDLesson] = []
        for reference in references {
            let lesson = try resolveLessonReference(reference, in: modelContext)
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
            modelContext.rollback()
            throw MCPToolError("The new order could not be saved.")
        }

        let carried = ordered.count - listed.count
        let note = carried > 0 ? " (\(carried) unlisted lesson(s) kept their order after them)" : ""
        return "\(label) now runs\(note):\n" + numberedLessonLines(ordered)
    }
}
