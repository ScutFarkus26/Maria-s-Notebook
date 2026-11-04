//
//  MCPNotebookTools+Reference.swift
//  Cosmic Daybook
//
//  The material a guide consults rather than edits day to day: written
//  procedures, the story shelf, and where each child stands on her lesson
//  sequences. Community topics moved to their own file when they gained a writer.
//
//  A child's standing on a sequence comes from SequenceStandingLoader, the
//  same reader the student page uses, so "mastered" and "next" mean the same
//  thing everywhere (2026-11-03; it used to read track enrollments).
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Procedures

    static func listProceduresTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_procedures",
            title: "List Procedures",
            description: "The classroom's written procedures — fire drill, dismissal, lunch, "
                + "material care. Returns the full text when a procedure is named.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "search": [
                        "type": "string",
                        "description": "Match against title, summary, or content"
                    ],
                    "category": [
                        "type": "string",
                        "description": "Only this category — Daily Routines, Safety & Emergency, and so on"
                    ],
                    "include_content": [
                        "type": "boolean",
                        "description": "Include each procedure's full text (default false)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeProcedures(arguments: arguments, in: context())
            }
        )
    }

    private static func describeProcedures(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let search: String? = nonEmpty(arguments["search"]?.stringValue)?.lowercased()
        let category: String? = nonEmpty(arguments["category"]?.stringValue)?.lowercased()
        let includeContent: Bool = arguments["include_content"]?.boolValue ?? false

        let all: [CDProcedure] = modelContext.safeFetch(CDFetchRequest(CDProcedure.self))
        var kept: [CDProcedure] = []
        for procedure in all {
            if let category, procedure.categoryRaw.lowercased() != category { continue }
            if let search, !procedureMatches(procedure, search) { continue }
            kept.append(procedure)
        }
        guard !kept.isEmpty else { return "No procedures match that." }

        let sorted: [CDProcedure] = kept.sorted { lhs, rhs in
            if lhs.categoryRaw != rhs.categoryRaw { return lhs.categoryRaw < rhs.categoryRaw }
            return lhs.title < rhs.title
        }
        // One clear match reads better in full than as a one-line summary.
        let showContent: Bool = includeContent || sorted.count == 1
        let lines = sorted.map { procedure -> String in
            let id: String = procedure.id?.uuidString ?? "unknown"
            let head: String = "- [procedure id=\(id)] \(procedure.title) (\(procedure.categoryRaw))"
            let summary: String = nonEmpty(procedure.summary).map { "\n    \($0)" } ?? ""
            guard showContent, let content = nonEmpty(procedure.content) else {
                return head + summary
            }
            return head + summary + "\n    " + content.replacingOccurrences(of: "\n", with: "\n    ")
        }
        return "\(sorted.count) procedure(s):\n" + lines.joined(separator: "\n")
    }

    private static func procedureMatches(_ procedure: CDProcedure, _ needle: String) -> Bool {
        if procedure.title.lowercased().contains(needle) { return true }
        if procedure.summary.lowercased().contains(needle) { return true }
        return procedure.content.lowercased().contains(needle)
    }

    // MARK: - Stories

    static func listStoriesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_stories",
            title: "List Stories",
            description: "The story shelf: read-alouds and picture books on file, with their "
                + "themes and grade range. The PDFs themselves are not returned.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "search": [
                        "type": "string",
                        "description": "Match against title, summary, or themes"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum stories to return, 1-100 (default 40)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeStories(arguments: arguments, in: context())
            }
        )
    }

    private static func describeStories(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let search: String? = nonEmpty(arguments["search"]?.stringValue)?.lowercased()
        let limit: Int = intArgument(arguments, "limit", default: 40, range: 1...100)

        let all: [CDStory] = modelContext.safeFetch(CDFetchRequest(CDStory.self))
        var kept: [CDStory] = []
        for story in all {
            if let search, !storyMatches(story, search) { continue }
            kept.append(story)
        }
        guard !kept.isEmpty else { return "No stories match that." }

        let sorted: [CDStory] = kept.sorted { $0.title < $1.title }
        let shown: [CDStory] = Array(sorted.prefix(limit))
        let lines = shown.map { story -> String in
            let id: String = story.id?.uuidString ?? "unknown"
            var details: [String] = []
            let themes: [String] = story.themesArray
            if !themes.isEmpty {
                details.append(themes.joined(separator: ", "))
            }
            if story.pageCount > 0 {
                details.append("\(story.pageCount) pages")
            }
            let suffix: String = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
            let summary: String = nonEmpty(story.summary).map { "\n    \($0)" } ?? ""
            return "- [story id=\(id)] \(story.title)\(suffix)\(summary)"
        }
        let more: String = sorted.count > shown.count
            ? "\n(\(sorted.count - shown.count) more not shown.)"
            : ""
        return "\(sorted.count) story/stories:\n" + lines.joined(separator: "\n") + more
    }

    private static func storyMatches(_ story: CDStory, _ needle: String) -> Bool {
        if story.title.lowercased().contains(needle) { return true }
        if story.summary.lowercased().contains(needle) { return true }
        for theme in story.themesArray where theme.lowercased().contains(needle) {
            return true
        }
        return false
    }

    // MARK: - Sequence Standing

    static func studentTracksTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_tracks",
            title: "Student Sequence Standing",
            description: "Where a student stands on the lesson sequences she has started: "
                + "how many lessons she has mastered and which lesson is next.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "include_inactive": [
                        "type": "boolean",
                        "description": "Also include sequences she has finished (default false)"
                    ]
                ],
                "required": ["student_name"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let student = try resolveStudentReference(
                    requireString(arguments, "student_name"), in: modelContext
                )
                let includeFinished = arguments["include_inactive"]?.boolValue ?? false
                return describeStandings(
                    for: student, includeFinished: includeFinished, in: modelContext
                )
            }
        )
    }

    /// One line per sequence the child has started, from her presentation
    /// record (`SequenceStandingLoader`): the ones in progress, and with
    /// `includeFinished` the ones she has mastered every lesson of.
    private static func describeStandings(
        for student: CDStudent, includeFinished: Bool, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let studentID = student.id else {
            return "That student record has no identifier."
        }
        let standings = SequenceStandingLoader.standings(forStudentID: studentID.uuidString, in: modelContext)
            .filter { $0.isInProgress || (includeFinished && $0.isFinished) }
        guard !standings.isEmpty else {
            return "\(student.fullName) has not started any lesson sequences."
        }
        let lines: [String] = standings.map(standingLine)
        return (["\(student.fullName)'s sequences:"] + lines).joined(separator: "\n")
    }

    private static func standingLine(_ standing: SequenceStanding) -> String {
        var details: [String] = ["\(standing.masteredCount)/\(standing.total) lessons mastered"]
        if standing.isFinished {
            details.append("complete")
        } else if let next = standing.nextLesson {
            details.append("next: \(next.name)")
        }
        return "- [sequence: \(standing.title)] \(details.joined(separator: "; "))"
    }
}
