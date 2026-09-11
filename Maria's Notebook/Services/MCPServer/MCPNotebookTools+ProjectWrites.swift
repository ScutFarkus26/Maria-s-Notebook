//
//  MCPNotebookTools+ProjectWrites.swift
//  Maria's Notebook
//
//  Starting a project, editing one, and putting a meeting on its calendar.
//  Split out of the reads in +Projects.swift to stay under the 400-line limit,
//  the same way +Work and +WorkWrites are split.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func updateProjectTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_project",
            title: "Create Or Update Project",
            description: "Start a project or edit one: its title, the book it follows, its "
                + "members, and whether it is still active. Pass project_id to edit; pass title "
                + "to start a new one.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "project_id": [
                        "type": "string",
                        "description": "The project to edit. Omit to start a new one."
                    ],
                    "title": ["type": "string", "description": "What the project is called"],
                    "book_title": ["type": "string", "description": "The book it follows, if any"],
                    "student_names": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Replace the project's members"
                    ],
                    "is_active": [
                        "type": "boolean",
                        "description": "Whether the project is still running"
                    ]
                ]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateProject(arguments: arguments, in: context())
            }
        )
    }

    private static func updateProject(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let project: CDProject
        let verb: String
        if let reference = nonEmpty(arguments["project_id"]?.stringValue) {
            project = try resolveProject(reference, in: modelContext)
            verb = "Updated"
        } else {
            guard nonEmpty(arguments["title"]?.stringValue) != nil else {
                throw MCPToolError("Starting a project needs a title.")
            }
            project = CDProject(context: modelContext)
            project.id = UUID()
            project.createdAt = Date()
            project.isActive = true
            verb = "Started"
        }

        var changes: [String] = []
        if let title = nonEmpty(arguments["title"]?.stringValue) {
            project.title = title
            changes.append("title")
        }
        if let book = arguments["book_title"]?.stringValue {
            project.bookTitle = book.trimmed()
            changes.append("book")
        }
        if let active = arguments["is_active"]?.boolValue {
            project.isActive = active
            changes.append(active ? "active" : "closed")
        }
        if let entries = arguments["student_names"]?.arrayValue {
            let names = entries.compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
            let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
            let ids = students.compactMap(\.id)
            guard ids.count == students.count else {
                throw MCPToolError("A matched student record has no identifier.")
            }
            project.memberStudentIDsArray = ids.map(\.uuidString)
            changes.append(students.isEmpty ? "cleared members" : "\(students.count) member(s)")
        }
        // Editing a project is itself activity: this stamp is what keeps a
        // project the guide has just touched out of the dormant pile.
        project.modifiedAt = Date()

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The project could not be saved.")
        }
        let id: String = project.id?.uuidString ?? "unknown"
        return "\(verb) [project id=\(id)] \(project.title): \(changes.joined(separator: ", "))."
    }

    static func addProjectSessionTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "add_project_session",
            title: "Add Project Session",
            description: "Schedule a project meeting: the day, what is being read, and the "
                + "agenda for it.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "project_id": [
                        "type": "string",
                        "description": "The project the session belongs to"
                    ],
                    "meeting_date": [
                        "type": "string",
                        "description": "The day it meets, YYYY-MM-DD"
                    ],
                    "chapter_or_pages": [
                        "type": "string",
                        "description": "What is being read or covered"
                    ],
                    "agenda_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "What the group will work through"
                    ]
                ],
                "required": ["project_id", "meeting_date"]
            ],
            annotations: .write,
            handler: { arguments in
                try addProjectSession(arguments: arguments, in: context())
            }
        )
    }

    private static func addProjectSession(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let project = try resolveProject(requireString(arguments, "project_id"), in: modelContext)
        guard let projectID = project.id else {
            throw MCPToolError("That project has no identifier.")
        }
        guard let meetingDate = try dayArgument(arguments, "meeting_date") else {
            throw MCPToolError("A meeting_date is required, formatted YYYY-MM-DD.")
        }

        let session = CDProjectSession(context: modelContext)
        session.id = UUID()
        session.projectID = projectID.uuidString
        session.createdAt = Date()
        session.meetingDate = meetingDate
        session.chapterOrPages = nonEmpty(arguments["chapter_or_pages"]?.stringValue)
        session.agendaItems = stringArrayArgument(arguments, "agenda_items")
        session.project = project

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The session could not be saved.")
        }
        let id: String = session.id?.uuidString ?? "unknown"
        let reading: String = nonEmpty(session.chapterOrPages).map { " on \($0)" } ?? ""
        return "Added [projectSession id=\(id)] to \(project.title): "
            + "\(dayString(meetingDate))\(reading)."
    }
}
