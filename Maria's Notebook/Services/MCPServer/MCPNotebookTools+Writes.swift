//
//  MCPNotebookTools+Writes.swift
//  Maria's Notebook
//
//  Write tools. Observation capture follows the same sanctioned path as
//  LogObservationIntent and QuickNoteViewModel: build the CDNote, set its
//  scope, sync student links, and save through safeSave so CloudKit
//  mirroring sees the change. Edits go through the same repositories the
//  in-app forms use (StudentRepository / NoteRepository). MCP clients
//  (Claude Desktop) show the teacher each tool call for approval before
//  it runs.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    static func createObservationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "create_observation",
            title: "Record Observation",
            description: "Record a new observation note about one or more students. "
                + "Writes to the teacher's notebook exactly as an in-app quick note would. "
                + "Pass a notes array to file several observations in one call, each with the "
                + "same fields. An observation identical to one already filed that day is "
                + "reported rather than duplicated, unless force is true.",
            inputSchema: createObservationSchema,
            annotations: .write,
            handler: { arguments in
                try recordObservation(arguments: arguments, in: context())
            }
        )
    }

    /// Both forms of the tool. `notes` resolves every item before writing any
    /// of them (MCPNotebookTools+ObservationBatch); without it the arguments
    /// are one observation, as they always were.
    private static func recordObservation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let force = arguments["force"]?.boolValue ?? false
        if let entries = arguments["notes"]?.arrayValue {
            let drafts = try observationDrafts(fromBatch: entries, in: modelContext)
            return try recordObservationBatch(drafts, force: force, in: modelContext)
        }

        let draft = try observationDraft(from: arguments, in: modelContext)
        if !force, let existing = existingObservation(
            body: draft.body, scope: draft.scope, on: draft.date, in: modelContext
        ) {
            return duplicateNotice(
                subject: "observation",
                citation: "[note id=\(citationID(existing.id))]",
                on: draft.date
            )
        }

        let note = insertObservation(draft, in: modelContext)
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The observation could not be saved.")
        }
        return "Recorded observation [note id=\(citationID(note.id))] about \(draft.names) "
            + "on \(dayString(draft.date))."
    }

    // MARK: - Update Student

    static func updateStudentTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_student",
            title: "Update Student",
            description: "Edit a student's profile: nickname, first or last name, birthday, or level. "
                + "Only the fields provided are changed.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student": [
                        "type": "string",
                        "description": "The student to edit: a name or nickname, or a student id from list_students"
                    ],
                    "nickname": [
                        "type": "string",
                        "description": "New nickname; pass an empty string to clear it"
                    ],
                    "first_name": ["type": "string", "description": "New first name"],
                    "last_name": ["type": "string", "description": "New last name"],
                    "birthday": ["type": "string", "description": "New birthday as YYYY-MM-DD"],
                    "level": ["type": "string", "description": "New level: \"lower\", \"upper\", or \"adolescent\""]
                ],
                "required": ["student"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateStudent(arguments: arguments, in: context())
            }
        )
    }

    private static func updateStudent(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "student")
        let student = try resolveStudentReference(reference, in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }

        let edits = try parseStudentEdits(from: arguments)
        guard !edits.descriptions.isEmpty else {
            throw MCPToolError(
                "No changes were provided. Pass nickname, first_name, last_name, birthday, or level."
            )
        }

        let repository = StudentRepository(context: modelContext)
        guard repository.updateStudent(
            id: studentID,
            firstName: edits.firstName,
            lastName: edits.lastName,
            birthday: edits.birthday,
            nickname: edits.nickname,
            level: edits.level
        ) else {
            throw MCPToolError("The student record could not be updated.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The student changes could not be saved.")
        }
        return "Updated \(student.fullName): \(edits.descriptions.joined(separator: ", "))."
    }

    private struct StudentEdits {
        var firstName: String?
        var lastName: String?
        var birthday: Date?
        var nickname: String?
        var level: CDStudent.Level?
        var descriptions: [String] = []
    }

    private static func parseStudentEdits(from arguments: [String: JSONValue]) throws -> StudentEdits {
        var edits = StudentEdits()
        // An empty nickname is meaningful (it clears the field), so read
        // the raw value rather than requireString.
        if let nickname = arguments["nickname"]?.stringValue?.trimmed() {
            edits.nickname = nickname
            edits.descriptions.append(nickname.isEmpty ? "cleared nickname" : "nickname → \"\(nickname)\"")
        }
        if let firstName = arguments["first_name"]?.stringValue?.trimmed(), !firstName.isEmpty {
            edits.firstName = firstName
            edits.descriptions.append("first name → \(firstName)")
        }
        if let lastName = arguments["last_name"]?.stringValue?.trimmed(), !lastName.isEmpty {
            edits.lastName = lastName
            edits.descriptions.append("last name → \(lastName)")
        }
        if let birthdayString = arguments["birthday"]?.stringValue?.trimmed(), !birthdayString.isEmpty {
            guard let birthday = isoDay.date(from: birthdayString) else {
                throw MCPToolError("Birthday must be formatted YYYY-MM-DD, got \"\(birthdayString)\".")
            }
            edits.birthday = birthday
            edits.descriptions.append("birthday → \(birthdayString)")
        }
        if let levelString = arguments["level"]?.stringValue?.trimmed(), !levelString.isEmpty {
            guard let level = CDStudent.Level.allCases.first(
                where: { $0.rawValue.lowercased() == levelString.lowercased() }
            ) else {
                let allowed = CDStudent.Level.allCases.map { $0.rawValue.lowercased() }
                    .joined(separator: ", ")
                throw MCPToolError("Level must be one of: \(allowed).")
            }
            edits.level = level
            edits.descriptions.append("level → \(level.rawValue.lowercased())")
        }
        return edits
    }

    /// Resolves a student from a tool argument that may be either an exact
    /// UUID (from list_students) or a name/nickname.
    static func resolveStudentReference(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDStudent {
        if let id = UUID(uuidString: reference) {
            guard let student = StudentRepository(context: modelContext).fetchStudent(id: id) else {
                throw MCPToolError("No student with id \(reference) was found.")
            }
            return student
        }
        return try resolveStudent(named: reference, in: modelContext)
    }

    // MARK: - Update Observation

    static func updateObservationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_observation",
            title: "Update Observation",
            description: "Edit an existing observation note by its id (as returned by "
                + "student_observations or search_notebook): its text, tags, flags, or which "
                + "children it is about. Only the fields provided are changed.",
            inputSchema: updateObservationSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateObservation(arguments: arguments, in: context())
            }
        )
    }

    private static let updateObservationSchema: JSONValue = [
        "type": "object",
        "properties": [
            "note_id": [
                "type": "string",
                "description": "The observation's UUID from another notebook tool"
            ],
            "body": ["type": "string", "description": "Replacement observation text"],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "description": .string("The children the note is about. This REPLACES the "
                    + "note's current children rather than adding to them, so name every "
                    + "child it should carry, including any already on it. An empty list "
                    + "widens the note to the whole class. Former students can be named "
                    + "here, since correcting an old note is the usual reason to reassign one.")
            ],
            "tags": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Replacement tag list (replaces all existing tags)"
            ],
            "needs_follow_up": [
                "type": "boolean",
                "description": "Flag or unflag the note for the follow-up inbox"
            ],
            "include_in_report": [
                "type": "boolean",
                "description": "Include or exclude the note from generated reports"
            ]
        ],
        "required": ["note_id"]
    ]

    private static func updateObservation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let idString = try requireString(arguments, "note_id")
        guard let noteID = UUID(uuidString: idString) else {
            throw MCPToolError("note_id must be a UUID from another notebook tool.")
        }

        // Parsed before the note is touched, so an unknown or ambiguous name
        // fails without leaving a half-applied edit behind.
        let edits = try parseNoteEdits(from: arguments, in: modelContext)
        guard !edits.descriptions.isEmpty else {
            throw MCPToolError(
                "No changes were provided. Pass body, student_names, tags, needs_follow_up, "
                    + "or include_in_report."
            )
        }

        let repository = NoteRepository(context: modelContext)
        guard let note = repository.fetchNote(id: noteID) else {
            throw MCPToolError("No observation with id \(idString) was found.")
        }
        // Reassigning the children leaves the presentation relationship alone,
        // the way UnifiedNoteEditor does: it attaches a note to its context
        // only when the note is first created, never on a later edit.
        let keptPresentationLink = edits.scope != nil && note.lessonAssignment != nil

        repository.updateNote(
            id: noteID,
            body: edits.body,
            tags: edits.tags,
            scope: edits.scope,
            includeInReport: edits.includeInReport,
            needsFollowUp: edits.needsFollowUp
        )
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The observation changes could not be saved.")
        }
        let linkNote = keptPresentationLink ? " Still linked to its presentation." : ""
        return "Updated observation [note id=\(idString)]: "
            + edits.descriptions.joined(separator: ", ") + ".\(linkNote)"
    }

    /// The parsed shape of an `update_observation` request: what to hand
    /// `NoteRepository`, and the receipt lines naming each change.
    private struct NoteEdits {
        var body: String?
        var tags: [String]?
        var scope: NoteScope?
        var includeInReport: Bool?
        var needsFollowUp: Bool?
        var descriptions: [String] = []
    }

    private static func parseNoteEdits(
        from arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> NoteEdits {
        var edits = NoteEdits()
        if let body = arguments["body"]?.stringValue?.trimmed() {
            guard !body.isEmpty else {
                throw MCPToolError("The replacement body cannot be empty.")
            }
            edits.body = body
            edits.descriptions.append("body")
        }
        if arguments["tags"] != nil {
            edits.tags = stringArrayArgument(arguments, "tags")
            edits.descriptions.append("tags")
        }
        if let needsFollowUp = arguments["needs_follow_up"]?.boolValue {
            edits.needsFollowUp = needsFollowUp
            edits.descriptions.append(needsFollowUp ? "flagged for follow-up" : "follow-up cleared")
        }
        if let includeInReport = arguments["include_in_report"]?.boolValue {
            edits.includeInReport = includeInReport
            edits.descriptions.append(includeInReport ? "included in reports" : "excluded from reports")
        }
        if let reassignment = try parseNoteScope(arguments, in: modelContext) {
            edits.scope = reassignment.scope
            edits.descriptions.append(reassignment.description)
        }
        return edits
    }

    /// Rebuilds the note's scope from `student_names`. The list replaces the
    /// note's children the way `update_todo` does, and an empty list widens the
    /// note to the whole class — the same reading `UnifiedNoteEditor` gives an
    /// empty selection.
    private static func parseNoteScope(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> (scope: NoteScope, description: String)? {
        guard let entries = arguments["student_names"]?.arrayValue else { return nil }
        let names = entries.compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let ids = students.compactMap(\.id)
        guard ids.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        guard !ids.isEmpty else {
            return (.all, "now a whole-class note")
        }
        let scope: NoteScope = ids.count == 1
            ? .student(ids[0])
            : .students(ids.sorted { $0.uuidString < $1.uuidString })
        return (scope, "now about \(students.map(\.fullName).joined(separator: ", "))")
    }
}
