//
//  MCPNotebookTools+CurriculumReads.swift
//  Cosmic Daybook
//
//  Reading a whole area or sub-area of the curriculum in taught order, with
//  no cap (`find_lessons` with `area`). A name search stops at 25 because it
//  answers "which lesson does the guide mean"; this answers "what is in the
//  notebook", which is what an album-versus-notebook comparison needs in one call.
//
//  Within a sub-area the lessons sit under their section headings, in the
//  same bands the scope map and the Checklist draw (`LessonSectionGrouping`:
//  each section where its earliest lesson falls, unsectioned runs in place),
//  because this is the only read that shows a lesson's `section` — without
//  it a section set over MCP could never be checked from outside the app.
//  Positions stay 1-based across the whole sub-area, so a number here is the
//  one reorder_lessons and create_lesson report.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// `find_lessons`' `area` and `sub_area` properties: a whole area (or one of its sub-areas) in
    /// sequence order with no result cap, in place of a name search.
    static let lessonsByAreaSchema: [String: JSONValue] = [
        "area": [
            "type": "string",
            "description": .string("List every lesson in this top-level area (e.g. \"Language\", \"Math\") in "
                + "sequence order with no result cap, instead of searching by query — to compare the notebook "
                + "against an album before create_lesson or reorder_lessons. Lines are numbered by position "
                + "within their sub-area (1-based). An area listing groups by sub-area in the order the scope "
                + "map shows them (set that order with reorder_lessons' sub_areas). Within a sub-area, lessons "
                + "that carry a section sit under a \"Section: <name>\" heading; each section sits where its "
                + "earliest lesson falls, and lessons with no section sit under \"No section\" wherever their "
                + "own order puts them (there can be several such runs). A sub-area with no sections is a "
                + "plain numbered list.")
        ],
        "sub_area": [
            "type": "string",
            "description": .string("With area: one sub-area (sequence) within it, e.g. \"Logical Analysis\". "
                + "Omit for the whole area.")
        ]
    ]

    static func listLessonsByArea(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lessons = allCurriculumLessons(in: modelContext)
        let area = try resolveArea(try requireString(arguments, "area"), from: lessons)
        // One read of every lesson's files for the whole listing, which has no cap.
        let files = LessonFileTitles(in: modelContext)

        if let subArea = nonEmpty(arguments["sub_area"]?.stringValue) {
            let sequence = try resolveSequence(subArea, inArea: area, from: lessons)
            let inSequence = lessonsInSequence(sequence, area: area, from: lessons)
            return sequenceBlock(sequence, area: area, lessons: inSequence, files: files)
        }

        let blocks = orderedSequences(inArea: area, from: lessons).map { sequence in
            sequenceBlock(
                sequence, area: area, lessons: lessonsInSequence(sequence, area: area, from: lessons), files: files
            )
        }
        let total = blocks.isEmpty ? 0 : lessons.filter { sameFiling($0.area, area) }.count
        return "\(area): \(total) lesson(s) in \(blocks.count) sub-area(s)\n\n" + blocks.joined(separator: "\n\n")
    }

    /// One sub-area: a header line, then its lessons under their section
    /// headings. `lessons` arrive in taught order and keep those positions
    /// whichever band they land in. A sub-area with no sections prints the
    /// plain numbered list it always did.
    private static func sequenceBlock(
        _ sequence: String, area: String, lessons: [CDLesson], files: LessonFileTitles
    ) -> String {
        let storedSequence: String = sequence == ungroupedSequenceLabel ? "" : sequence
        let header = "\(filingLabel(area: area, sequence: storedSequence)) — \(lessons.count) lesson(s)"
        let bands = LessonSectionGrouping.bands(for: lessons)
        guard bands.contains(where: { !$0.name.isEmpty }) else {
            return header + "\n" + numberedLessonLines(lessons, files: files)
        }
        let positions: [NSManagedObjectID: Int] = Dictionary(
            uniqueKeysWithValues: lessons.enumerated().map { ($0.element.objectID, $0.offset + 1) }
        )
        let blocks: [String] = bands.map { band in
            let heading: String = band.name.isEmpty ? "No section" : "Section: \(band.name)"
            let lines: [String] = band.lessons.map { lesson in
                "\(positions[lesson.objectID] ?? 0). \(describeLesson(lesson))\(files.suffix(for: lesson))"
            }
            return ([heading] + lines).joined(separator: "\n")
        }
        return header + "\n" + blocks.joined(separator: "\n")
    }
}
