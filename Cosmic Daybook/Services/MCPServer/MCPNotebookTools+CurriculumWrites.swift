//
//  MCPNotebookTools+CurriculumWrites.swift
//  Cosmic Daybook
//
//  Adding a lesson to the curriculum and editing one. Both write through
//  `LessonRepository` and settle the ordering columns the way the Lessons
//  screens do (see +CurriculumSupport), then make the same best-effort track
//  refresh AddLessonView makes, so a lesson added from an album over MCP
//  looks exactly like one typed into the bulk-entry sheet.
//
//  create_lesson is idempotent on name within a sub-area and never deletes;
//  a sub-area is created on demand but a top-level area never is.
//  update_lesson changes only the fields passed, and refuses a rename or move
//  that would put two lessons with one name in one sub-area. Renames are
//  safe: every presentation, plan, work item, note and track step references
//  the lesson by its id, never its name.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Create Lesson

    static func createLessonTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "create_lesson",
            title: "Create Lesson",
            description: "Add a lesson to the curriculum under an existing area and a sub-area "
                + "(created under that area if new). Idempotent: a lesson already filed under "
                + "that sub-area with the same name is returned rather than duplicated. New "
                + "lessons go to the end of the sub-area unless after_lesson places them. Never "
                + "creates a top-level area — an unknown area is refused with the list of "
                + "existing ones. Never deletes anything.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "The lesson's name as the album gives it"],
                    "area": ["type": "string", "description": "An existing top-level area, e.g. \"Language\""],
                    "sub_area": [
                        "type": "string",
                        "description": .string("The sub-area (sequence) within the area, e.g. \"Logical "
                            + "Analysis\"; \"Ungrouped\" files it with no sub-area")
                    ],
                    "after_lesson": [
                        "type": "string",
                        "description": .string("Id (from find_lessons or list_lessons_by_area) or exact "
                            + "name of the lesson this one follows. It must be in the same sub-area. "
                            + "Omit to append at the end.")
                    ],
                    "section": ["type": "string", "description": "Optional section heading within the sub-area"],
                    "write_up": ["type": "string", "description": "The lesson's write-up or description"],
                    "teacher_notes": ["type": "string", "description": "The guide's own notes on the lesson"],
                    "purpose": ["type": "string", "description": "Direct and indirect aims"],
                    "materials": ["type": "string", "description": "Materials, one per line"],
                    "is_key_lesson": [
                        "type": "boolean",
                        "description": .string("Mark it a key lesson — a milestone the Three-Year View "
                            + "shows by default (the first lesson of a sub-area counts without marking)")
                    ]
                ],
                "required": ["name", "area", "sub_area"]
            ],
            annotations: .write,
            handler: { arguments in
                try undoingOnFailure(context()) { try createLesson(arguments: arguments, in: $0) }
            }
        )
    }

    private static func createLesson(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let name = try requireString(arguments, "name")
        let lessons = allCurriculumLessons(in: modelContext)
        let area = try resolveArea(try requireString(arguments, "area"), from: lessons)
        let requestedSequence = storedSequence(forArgument: try requireString(arguments, "sub_area"))
        let existingSequence = existingSequence(named: requestedSequence, inArea: area, from: lessons)
        let sequence = existingSequence ?? requestedSequence

        var inSequence = lessonsInSequence(sequence, area: area, from: lessons)
        if let existing = inSequence.first(where: { $0.name.folded() == name.folded() }) {
            let position = (inSequence.firstIndex(of: existing) ?? 0) + 1
            MCPCallOutcome.markNothingWritten()
            return "Already in the curriculum, nothing added: \(describeLesson(existing)) "
                + "(position \(position) of \(inSequence.count))."
        }

        let anchor: CDLesson? = try resolveAnchor(arguments, area: area, sequence: sequence, in: modelContext)
        let lesson: CDLesson = try makeLesson(arguments, name: name, area: area, sequence: sequence, in: modelContext)
        let isKeyLesson: Bool = arguments["is_key_lesson"]?.boolValue ?? false
        lesson.isKeyLesson = isKeyLesson
        let anchorIndex: Int? = anchor.flatMap { inSequence.firstIndex(of: $0) }
        let insertAt: Int = anchorIndex.map { $0 + 1 } ?? inSequence.count
        inSequence.insert(lesson, at: insertAt)
        renumberSequence(inSequence)
        rebuildSortIndex(forArea: area, from: lessons + [lesson])

        guard modelContext.safeSave() else {
            throw MCPToolError("The lesson could not be saved.")
        }
        refreshSequenceTrack(area: area, sequence: sequence, in: modelContext)

        let newSubArea = existingSequence == nil && !sequence.isEmpty ? " (new sub-area)" : ""
        return "Added \(describeLesson(lesson)) at position \(insertAt + 1) of \(inSequence.count) "
            + "in \(filingLabel(area: area, sequence: sequence))\(newSubArea)."
    }

    /// The lesson `after_lesson` names, which must sit in the target sub-area.
    private static func resolveAnchor(
        _ arguments: [String: JSONValue], area: String, sequence: String, in modelContext: NSManagedObjectContext
    ) throws -> CDLesson? {
        guard let reference = nonEmpty(arguments["after_lesson"]?.stringValue) else { return nil }
        let lesson = try resolveLessonReference(reference, in: modelContext)
        guard sameFiling(lesson.area, area), sameFiling(lesson.sequence, sequence) else {
            let label = filingLabel(area: area, sequence: sequence)
            throw MCPToolError(
                "after_lesson \(describeLesson(lesson)) is not in \(label). "
                    + "Pass a lesson from the same sub-area, or omit it to append at the end."
            )
        }
        return lesson
    }

    /// `LessonRepository.createLesson` with AddLessonView's defaults (album
    /// source, standard format); ordering is settled by the caller. The
    /// repository's own one-name-per-sub-area rule backs the idempotency
    /// check above, so a race between two filings cannot double a lesson.
    private static func makeLesson(
        _ arguments: [String: JSONValue], name: String, area: String, sequence: String,
        in modelContext: NSManagedObjectContext
    ) throws -> CDLesson {
        let section: String = arguments["section"]?.stringValue?.trimmed() ?? ""
        let writeUp: String = arguments["write_up"]?.stringValue ?? ""
        let materials: String = arguments["materials"]?.stringValue ?? ""
        let purpose: String = arguments["purpose"]?.stringValue?.trimmed() ?? ""
        let teacherNotes: String = arguments["teacher_notes"]?.stringValue ?? ""
        do {
            return try LessonRepository(context: modelContext).createLesson(
                name: name, area: area, sequence: sequence, section: section, writeUp: writeUp,
                materials: materials, purpose: purpose, teacherNotes: teacherNotes
            )
        } catch {
            throw MCPToolError(nil, underlying: error)
        }
    }

    // MARK: - Update Lesson

    static func updateLessonTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_lesson",
            title: "Update Lesson",
            description: "Rename a lesson, move it to another sub-area (or area), or change its "
                + "notes. Only the fields passed change. A move puts the lesson at the end of its "
                + "new sub-area; use reorder_lessons to place it. A rename or move onto a name the "
                + "sub-area already has is refused. Presentations, plans, work and tracks reference "
                + "the lesson by id, so a rename breaks nothing.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson": ["type": "string", "description": "Lesson id or exact name"],
                    "name": ["type": "string", "description": "New name"],
                    "area": [
                        "type": "string",
                        "description": "Move to this existing area (pass sub_area too). Never creates an area."
                    ],
                    "sub_area": [
                        "type": "string",
                        "description": "Move to this sub-area, created if new (\"Ungrouped\" means none)"
                    ],
                    "section": ["type": "string", "description": "Section heading; empty string clears it"],
                    "write_up": ["type": "string", "description": "Replaces the write-up; empty string clears it"],
                    "teacher_notes": ["type": "string", "description": "Replaces the notes; empty string clears"],
                    "purpose": ["type": "string", "description": "Replaces the purpose; empty string clears"],
                    "materials": ["type": "string", "description": "Replaces materials; empty string clears"],
                    "is_key_lesson": [
                        "type": "boolean",
                        "description": .string("Mark or unmark the lesson as a key lesson, a milestone the "
                            + "Three-Year View shows by default")
                    ]
                ],
                "required": ["lesson"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { try updateLesson(arguments: arguments, in: $0) }
            }
        )
    }

    private static func updateLesson(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lesson = try resolveLessonReference(try requireString(arguments, "lesson"), in: modelContext)
        let lessons = allCurriculumLessons(in: modelContext)
        let newName: String? = nonEmpty(arguments["name"]?.stringValue).flatMap { $0 == lesson.name ? nil : $0 }
        let move: LessonFiling? = try lessonFilingTarget(arguments, for: lesson, from: lessons)
        if newName != nil || move != nil {
            try refuseTwin(
                of: lesson, named: newName ?? lesson.name,
                area: move?.area ?? lesson.area, sequence: move?.sequence ?? lesson.sequence, in: modelContext
            )
        }

        var changes: [String] = []
        changes += applyLessonText(arguments, to: lesson)
        if let isKey = arguments["is_key_lesson"]?.boolValue, isKey != lesson.isKeyLesson {
            lesson.isKeyLesson = isKey
            changes.append(isKey ? "marked as a key lesson" : "no longer a key lesson")
        }
        if let move {
            changes.append(applyLessonFiling(move, to: lesson, from: lessons))
        }
        if let newName {
            changes.append("renamed \"\(lesson.name)\" to \"\(newName)\"")
            lesson.name = newName
        }
        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard modelContext.safeSave() else {
            throw MCPToolError("The lesson could not be saved.")
        }
        return "Updated \(describeLesson(lesson)): \(changes.joined(separator: "; "))."
    }

    /// A rename or move that would leave two lessons with one name in one
    /// sub-area is refused in Add Lesson's words: the launch cleanup reads
    /// such a pair as one lesson filed twice and merges it away (bug hunt
    /// 2026-10-12, #2). Checked on the final name and filing, before anything
    /// changes. Parsha lessons are keyed by week and exempt, as in Add Lesson.
    /// The lesson editor's own check decides, so a rename that keeps the
    /// lesson's name key (only its capitals change, say, in a pair filed
    /// before the check) saves here as it does there.
    private static func refuseTwin(
        of lesson: CDLesson, named name: String, area: String, sequence: String,
        in modelContext: NSManagedObjectContext
    ) throws {
        let repository = LessonRepository(context: modelContext)
        do {
            try repository.refuseDuplicateName(filing: lesson, as: name, area: area, sequence: sequence)
        } catch {
            let sentence: String = error.errorDescription ?? "That name is already in that sub-area."
            let there: String = repository
                .existingLesson(named: name, area: area, sequence: sequence, excluding: lesson)
                .map { " The lesson there: \(describeLesson($0))." } ?? ""
            throw MCPToolError("\(sentence) Nothing was changed.\(there)")
        }
    }

    /// One free-text lesson field: the tool argument that carries it, the word
    /// the change log uses for it, and where it is stored.
    private struct LessonTextField {
        let key: String
        let label: String
        let keyPath: ReferenceWritableKeyPath<CDLesson, String>
    }

    /// Notes fields replace wholesale; an empty string clears, so the raw
    /// value is read rather than `nonEmpty`.
    private static func applyLessonText(_ arguments: [String: JSONValue], to lesson: CDLesson) -> [String] {
        var changes: [String] = []
        if let section = arguments["section"]?.stringValue?.trimmed(), section != lesson.section {
            lesson.section = section
            changes.append(section.isEmpty ? "cleared section" : "section \(section)")
        }
        let notes: [LessonTextField] = [
            LessonTextField(key: "write_up", label: "write-up", keyPath: \.writeUp),
            LessonTextField(key: "teacher_notes", label: "teacher notes", keyPath: \.teacherNotes),
            LessonTextField(key: "purpose", label: "purpose", keyPath: \.purpose),
            LessonTextField(key: "materials", label: "materials", keyPath: \.materials)
        ]
        for field in notes {
            guard let value = arguments[field.key]?.stringValue,
                  value != lesson[keyPath: field.keyPath] else { continue }
            lesson[keyPath: field.keyPath] = value
            changes.append(value.trimmed().isEmpty ? "cleared \(field.label)" : "\(field.label)")
        }
        return changes
    }

    /// Where a move sends a lesson.
    private struct LessonFiling {
        let area: String
        let sequence: String
    }

    /// The area and sub-area `area` / `sub_area` name, in the spelling the
    /// curriculum already uses, or nil when they name the lesson's own filing.
    /// "Ungrouped" means no sub-area (#26).
    private static func lessonFilingTarget(
        _ arguments: [String: JSONValue], for lesson: CDLesson, from lessons: [CDLesson]
    ) throws -> LessonFiling? {
        let areaArgument = nonEmpty(arguments["area"]?.stringValue)
        let subAreaArgument = nonEmpty(arguments["sub_area"]?.stringValue).map(storedSequence(forArgument:))
        guard areaArgument != nil || subAreaArgument != nil else { return nil }
        if areaArgument != nil, subAreaArgument == nil {
            throw MCPToolError("Moving a lesson to another area needs sub_area as well.")
        }
        let area = try areaArgument.map { try resolveArea($0, from: lessons) } ?? lesson.area
        let requested = subAreaArgument ?? lesson.sequence
        let sequence = existingSequence(named: requested, inArea: area, from: lessons) ?? requested
        guard !(sameFiling(area, lesson.area) && sameFiling(sequence, lesson.sequence)) else { return nil }
        return LessonFiling(area: area, sequence: sequence)
    }

    /// A move mirrors `LessonsRootView.moveLessonToSequence`: the lesson goes
    /// to the end of its new sub-area and both areas' `sortIndex` are rebuilt.
    private static func applyLessonFiling(
        _ move: LessonFiling, to lesson: CDLesson, from lessons: [CDLesson]
    ) -> String {
        let oldArea = lesson.area
        let from = filingLabel(area: lesson.area, sequence: lesson.sequence)
        let target = lessonsInSequence(move.sequence, area: move.area, from: lessons).filter { $0 != lesson }
        lesson.area = move.area
        lesson.sequence = move.sequence
        lesson.orderInSequence = (target.map(\.orderInSequence).max() ?? -1) + 1
        rebuildSortIndex(forArea: oldArea, from: lessons)
        if !sameFiling(oldArea, move.area) { rebuildSortIndex(forArea: move.area, from: lessons) }
        return "moved from \(from) to \(filingLabel(area: move.area, sequence: move.sequence)) (end)"
    }
}
