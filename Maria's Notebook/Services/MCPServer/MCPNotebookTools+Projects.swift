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
                + "when they last met or next meet. Only projects still running are listed — one "
                + "with no session or edit since this school year began is dormant, not current — "
                + "and members are the children still enrolled.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "include_inactive": [
                        "type": "boolean",
                        "description": .string("Also list dormant projects (nothing since this school "
                            + "year began) and ones marked complete, and name members who have since "
                            + "left the class (default false)")
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "Only projects this student is a member of"
                    ]
                ]
            ],
            annotations: .readOnly,
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
            // `isActive` alone only says nobody pressed Mark Complete, so the
            // year-old sessionless projects all called themselves current.
            if !includeInactive, ProjectActivity.status(of: project) != .active { continue }
            // Membership filtering reads the raw id list on purpose: asking
            // after a child who has left should still find the project she was
            // part of, even though her name no longer prints by default.
            if let studentID = student?.id,
               !project.memberStudentIDsArray.contains(studentID.uuidString) { continue }
            kept.append(project)
        }
        guard !kept.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            let hint = includeInactive ? "" : " (dormant and completed ones are hidden — "
                + "pass include_inactive: true to see them)"
            return "No projects\(who).\(hint)"
        }

        let students = studentIndex(in: modelContext)
        let sorted: [CDProject] = kept.sorted { $0.title < $1.title }
        let lines = sorted.map { project -> String in
            projectLine(project, students: students, includeInactive: includeInactive)
        }
        return "\(sorted.count) project(s):\n" + lines.joined(separator: "\n")
    }

    private static func projectLine(
        _ project: CDProject, students: [String: CDStudent], includeInactive: Bool
    ) -> String {
        let id: String = project.id?.uuidString ?? "unknown"
        var details: [String] = []
        if let book = nonEmpty(project.bookTitle) {
            details.append("reading \(book)")
        }
        details.append(memberSummary(of: project, students: students, includeFormer: includeInactive))
        let sessions: [CDProjectSession] = projectSessions(of: project)
        details.append("\(sessions.count) session(s)")
        if let next = nextMeeting(among: sessions) {
            details.append("next \(dayString(next))")
        } else if let last = lastMeeting(among: sessions) {
            details.append("last met \(dayString(last))")
        }
        if let standing = statusText(of: project) {
            details.append(standing)
        }
        return "- [project id=\(id)] \(project.title) (\(details.joined(separator: "; ")))"
    }

    /// The project's standing, or nil when it is simply running — an active
    /// project needs no label.
    static func statusText(of project: CDProject) -> String? {
        switch ProjectActivity.status(of: project) {
        case .active:
            return nil
        case .closed:
            return "closed"
        case .dormant(let since):
            return since.map { "dormant since \(dayString($0))" } ?? "dormant"
        }
    }

    /// Who is in the project now.
    ///
    /// The member id list keeps every child ever added, so a withdrawn or
    /// transferred girl went on reading as a current member long after she
    /// left. By default only the enrolled are named; `include_inactive` names
    /// the rest as "(former)" rather than dropping them, so a project that has
    /// lost its whole group still says who it was.
    static func memberSummary(
        of project: CDProject, students: [String: CDStudent], includeFormer: Bool
    ) -> String {
        let members = project.memberStudentIDsArray.compactMap { students[$0] }
        let current = members.filter(\.isEnrolled).map(\.fullName).sorted()
        let former = members.filter { !$0.isEnrolled }.map { "\($0.fullName) (former)" }.sorted()
        if includeFormer {
            let all = current + former
            return all.isEmpty ? "no members" : all.joined(separator: ", ")
        }
        if current.isEmpty {
            return former.isEmpty ? "no members" : "no current members"
        }
        return current.joined(separator: ", ")
    }

    /// Student id string → record, so a member can be judged enrolled or not
    /// rather than merely named.
    static func studentIndex(in modelContext: NSManagedObjectContext) -> [String: CDStudent] {
        let students = modelContext.safeFetch(CDFetchRequest(CDStudent.self))
        return Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString, student) } },
            uniquingKeysWith: { first, _ in first }
        )
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
            annotations: .readOnly,
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
        let students = studentIndex(in: modelContext)
        let id: String = project.id?.uuidString ?? "unknown"
        var lines: [String] = ["[project id=\(id)] \(project.title)"]
        if let book = nonEmpty(project.bookTitle) {
            lines.append("  Reading: \(book)")
        }
        // A caller who named this one project wants the whole roster, so a
        // child who has since left is named and marked rather than dropped.
        lines.append(
            "  Members: " + memberSummary(of: project, students: students, includeFormer: true)
        )
        switch ProjectActivity.status(of: project) {
        case .active:
            break
        case .closed:
            lines.append("  This project has been marked complete.")
        case .dormant(let since):
            let when = since.map { " — nothing since \(dayString($0))" } ?? ""
            lines.append("  Dormant: no session or edit this school year\(when).")
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

    // MARK: - Resolving
    //
    // The writes — update_project and add_project_session — are in
    // +ProjectWrites.swift.

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
