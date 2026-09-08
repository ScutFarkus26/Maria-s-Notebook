//
//  MCPNotebookTools+Projects.swift
//  Maria's Notebook
//
//  Long-running group projects and the sessions they meet in — book studies,
//  research groups, anything a set of children carries across weeks.
//
//  A session's agenda is stored as JSON on the entity; the tools read and
//  write it through `agendaItems`, never by touching `agendaItemsJSON`.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Projects

    static func listProjectsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_projects",
            title: "List Projects",
            description: "The class's group projects: who is in each, what is being read, and "
                + "when they last met or next meet.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "include_inactive": [
                        "type": "boolean",
                        "description": "Also list finished or archived projects (default false)"
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "Only projects this student is a member of"
                    ]
                ]
            ],
            handler: { arguments in
                let modelContext = context()
                let includeInactive = arguments["include_inactive"]?.boolValue ?? false
                let student = try nonEmpty(arguments["student_name"]?.stringValue)
                    .map { try resolveStudentReference($0, in: modelContext) }
                return describeProjects(
                    includeInactive: includeInactive, student: student, in: modelContext
                )
            }
        )
    }

    private static func describeProjects(
        includeInactive: Bool, student: CDStudent?, in modelContext: NSManagedObjectContext
    ) -> String {
        let all: [CDProject] = modelContext.safeFetch(CDFetchRequest(CDProject.self))
        var kept: [CDProject] = []
        for project in all {
            if !includeInactive && !project.isActive { continue }
            if let studentID = student?.id,
               !project.memberStudentIDsArray.contains(studentID.uuidString) { continue }
            kept.append(project)
        }
        guard !kept.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return "No projects\(who)."
        }

        let names = studentNameIndex(in: modelContext)
        let sorted: [CDProject] = kept.sorted { $0.title < $1.title }
        let lines = sorted.map { project -> String in
            let id: String = project.id?.uuidString ?? "unknown"
            var details: [String] = []
            if let book = nonEmpty(project.bookTitle) {
                details.append("reading \(book)")
            }
            let members: [String] = project.memberStudentIDsArray.compactMap { names[$0] }.sorted()
            details.append(members.isEmpty ? "no members" : members.joined(separator: ", "))
            let sessions: [CDProjectSession] = projectSessions(of: project)
            details.append("\(sessions.count) session(s)")
            if let next = nextMeeting(among: sessions) {
                details.append("next \(dayString(next))")
            } else if let last = lastMeeting(among: sessions) {
                details.append("last met \(dayString(last))")
            }
            if !project.isActive {
                details.append("inactive")
            }
            return "- [project id=\(id)] \(project.title) (\(details.joined(separator: "; ")))"
        }
        return "\(sorted.count) project(s):\n" + lines.joined(separator: "\n")
    }

    static func projectSessions(of project: CDProject) -> [CDProjectSession] {
        (project.sessions?.allObjects as? [CDProjectSession]) ?? []
    }

    private static func nextMeeting(among sessions: [CDProjectSession]) -> Date? {
        let today: Date = AppCalendar.startOfDay(Date())
        var soonest: Date?
        for session in sessions {
            guard let date = session.meetingDate, date >= today else { continue }
            if soonest == nil || date < (soonest ?? .distantFuture) { soonest = date }
        }
        return soonest
    }

    private static func lastMeeting(among sessions: [CDProjectSession]) -> Date? {
        var latest: Date?
        for session in sessions {
            guard let date = session.meetingDate else { continue }
            if latest == nil || date > (latest ?? .distantPast) { latest = date }
        }
        return latest
    }

    // MARK: - One Project

    static func projectDetailTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "project_detail",
            title: "Project Detail",
            description: "One project in full: its members, every session with its reading and "
                + "agenda, and the notes taken in those sessions.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "project_id": [
                        "type": "string",
                        "description": "The project's id, as returned by list_projects"
                    ]
                ],
                "required": ["project_id"]
            ],
            handler: { arguments in
                let modelContext = context()
                let project = try resolveProject(
                    requireString(arguments, "project_id"), in: modelContext
                )
                return describeProjectDetail(project, in: modelContext)
            }
        )
    }

    private static func describeProjectDetail(
        _ project: CDProject, in modelContext: NSManagedObjectContext
    ) -> String {
        let names = studentNameIndex(in: modelContext)
        let id: String = project.id?.uuidString ?? "unknown"
        var lines: [String] = ["[project id=\(id)] \(project.title)"]
        if let book = nonEmpty(project.bookTitle) {
            lines.append("  Reading: \(book)")
        }
        let members: [String] = project.memberStudentIDsArray.compactMap { names[$0] }.sorted()
        lines.append("  Members: " + (members.isEmpty ? "none" : members.joined(separator: ", ")))
        if !project.isActive {
            lines.append("  This project is no longer active.")
        }

        let sessions: [CDProjectSession] = projectSessions(of: project).sorted { lhs, rhs in
            (lhs.meetingDate ?? .distantPast) < (rhs.meetingDate ?? .distantPast)
        }
        guard !sessions.isEmpty else {
            lines.append("  No sessions have been planned.")
            return lines.joined(separator: "\n")
        }

        lines.append("  Sessions:")
        for session in sessions {
            lines.append(contentsOf: sessionLines(session))
        }
        return lines.joined(separator: "\n")
    }

    private static func sessionLines(_ session: CDProjectSession) -> [String] {
        let sessionID: String = session.id?.uuidString ?? "unknown"
        let reading: String = nonEmpty(session.chapterOrPages).map { " — \($0)" } ?? ""
        var lines: [String] = ["    - [projectSession id=\(sessionID)] \(dayString(session.meetingDate))\(reading)"]
        for item in session.agendaItems where !item.trimmed().isEmpty {
            lines.append("        • \(item)")
        }
        let notes: [CDNote] = (session.noteItems?.allObjects as? [CDNote]) ?? []
        for note in notes where !note.body.trimmed().isEmpty {
            let noteID: String = note.id?.uuidString ?? "unknown"
            lines.append("        [note id=\(noteID)] \(note.body.trimmed())")
        }
        return lines
    }

    // MARK: - Writing

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

    static func resolveProject(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDProject {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("project_id must be a uuid, got \"\(reference)\".")
        }
        let request = CDFetchRequest(CDProject.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let project = modelContext.safeFetch(request).first else {
            throw MCPToolError("No project with id \(reference) was found.")
        }
        return project
    }
}
