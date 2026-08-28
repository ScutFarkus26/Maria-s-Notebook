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
                + "Writes to the teacher's notebook exactly as an in-app quick note would.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_names": [
                        "type": "array",
                        "items": ["type": "string"],
                        "minItems": 1,
                        "description": "First names, full names, or nicknames of the students observed"
                    ],
                    "body": [
                        "type": "string",
                        "description": "The observation text, as the teacher phrased it"
                    ],
                    "tags": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Optional tags to file the note under"
                    ],
                    "needs_follow_up": [
                        "type": "boolean",
                        "description": "Flag the note for the follow-up inbox (default false)"
                    ]
                ],
                "required": ["student_names", "body"]
            ],
            handler: { arguments in
                try recordObservation(arguments: arguments, in: context())
            }
        )
    }

    @MainActor
    private static func recordObservation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let body = try requireString(arguments, "body")
        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }

        let students = try names.map { try resolveStudent(named: $0, in: modelContext) }
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }

        let note = CDNote(context: modelContext)
        note.createdAt = Date()
        note.body = body
        note.scope = studentIDs.count == 1
            ? .student(studentIDs[0])
            : .students(studentIDs.sorted { $0.uuidString < $1.uuidString })
        let tags = stringArrayArgument(arguments, "tags")
        if !tags.isEmpty {
            note.tagsArray = tags
        }
        note.needsFollowUp = arguments["needs_follow_up"]?.boolValue ?? false
        note.syncStudentLinks(in: modelContext)

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The observation could not be saved.")
        }

        let who = students.map(\.fullName).joined(separator: ", ")
        let id = note.id?.uuidString ?? "unknown"
        return "Recorded observation [note id=\(id)] about \(who)."
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
            handler: { arguments in
                try updateStudent(arguments: arguments, in: context())
            }
        )
    }

    @MainActor
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

    @MainActor
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
    @MainActor
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
                + "student_observations or search_notebook). Only the fields provided are changed.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "note_id": [
                        "type": "string",
                        "description": "The observation's UUID from another notebook tool"
                    ],
                    "body": ["type": "string", "description": "Replacement observation text"],
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
            ],
            handler: { arguments in
                try updateObservation(arguments: arguments, in: context())
            }
        )
    }

    @MainActor
    private static func updateObservation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let idString = try requireString(arguments, "note_id")
        guard let noteID = UUID(uuidString: idString) else {
            throw MCPToolError("note_id must be a UUID from another notebook tool.")
        }

        let body = arguments["body"]?.stringValue?.trimmed()
        if let body, body.isEmpty {
            throw MCPToolError("The replacement body cannot be empty.")
        }
        let tags = arguments["tags"].map { _ in stringArrayArgument(arguments, "tags") }
        let needsFollowUp = arguments["needs_follow_up"]?.boolValue
        let includeInReport = arguments["include_in_report"]?.boolValue

        var descriptions: [String] = []
        if body != nil { descriptions.append("body") }
        if tags != nil { descriptions.append("tags") }
        if let needsFollowUp { descriptions.append(needsFollowUp ? "flagged for follow-up" : "follow-up cleared") }
        if let includeInReport {
            descriptions.append(includeInReport ? "included in reports" : "excluded from reports")
        }
        guard !descriptions.isEmpty else {
            throw MCPToolError(
                "No changes were provided. Pass body, tags, needs_follow_up, or include_in_report."
            )
        }

        guard NoteRepository(context: modelContext).updateNote(
            id: noteID,
            body: body,
            tags: tags,
            includeInReport: includeInReport,
            needsFollowUp: needsFollowUp
        ) else {
            throw MCPToolError("No observation with id \(idString) was found.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The observation changes could not be saved.")
        }
        return "Updated observation [note id=\(idString)]: \(descriptions.joined(separator: ", "))."
    }
}
