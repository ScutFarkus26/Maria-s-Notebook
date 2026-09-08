//
//  MCPNotebookTools+Reference.swift
//  Maria's Notebook
//
//  The material a guide consults rather than edits day to day: written
//  procedures, the story shelf, community topics the class has discussed, and
//  where each child stands on their sequence tracks.
//
//  Track progress goes through TrackProgressResolver, the same helper the
//  progression screens use, so "mastered" means the same thing everywhere.
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

    // MARK: - Community Topics

    static func communityTopicsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "community_topics",
            title: "Community Topics",
            description: "Topics the class has raised for community meeting — who brought each "
                + "one, the solutions proposed, and how it was settled.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "unaddressed_only": [
                        "type": "boolean",
                        "description": "Only topics not yet discussed (default false)"
                    ]
                ]
            ],
            handler: { arguments in
                describeCommunityTopics(arguments: arguments, in: context())
            }
        )
    }

    private static func describeCommunityTopics(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let unaddressedOnly: Bool = arguments["unaddressed_only"]?.boolValue ?? false
        let all: [CDCommunityTopicEntity] = modelContext
            .safeFetch(CDFetchRequest(CDCommunityTopicEntity.self))
        var kept: [CDCommunityTopicEntity] = []
        for topic in all {
            if unaddressedOnly && topic.addressedDate != nil { continue }
            kept.append(topic)
        }
        guard !kept.isEmpty else {
            return unaddressedOnly ? "Every topic has been addressed." : "No community topics yet."
        }

        let sorted: [CDCommunityTopicEntity] = kept.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        let lines = sorted.map { topic -> String in
            let id: String = topic.id?.uuidString ?? "unknown"
            var details: [String] = []
            if let broughtBy = nonEmpty(topic.broughtBy) {
                details.append("raised by \(broughtBy)")
            }
            if let addressed = topic.addressedDate {
                details.append("discussed \(dayString(addressed))")
            } else {
                details.append("not yet discussed")
            }
            let solutions: [CDProposedSolutionEntity] =
                (topic.proposedSolutions?.allObjects as? [CDProposedSolutionEntity]) ?? []
            if !solutions.isEmpty {
                details.append("\(solutions.count) proposed solution(s)")
            }
            let resolution: String = nonEmpty(topic.resolution)
                .map { "\n    Resolution: \($0)" } ?? ""
            return "- [communityTopic id=\(id)] \(topic.title) "
                + "(\(details.joined(separator: "; ")))\(resolution)"
        }
        return "\(sorted.count) topic(s):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Track Progress

    static func studentTracksTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_tracks",
            title: "Student Track Progress",
            description: "Where a student stands on the sequence tracks they are enrolled in: "
                + "how many steps they have mastered and which step is next.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "include_inactive": [
                        "type": "boolean",
                        "description": "Also include tracks they have finished or left (default false)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                let modelContext = context()
                let student = try resolveStudentReference(
                    requireString(arguments, "student_name"), in: modelContext
                )
                let includeInactive = arguments["include_inactive"]?.boolValue ?? false
                return describeTracks(
                    for: student, includeInactive: includeInactive, in: modelContext
                )
            }
        )
    }

    private static func describeTracks(
        for student: CDStudent, includeInactive: Bool, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let studentID = student.id else {
            return "That student record has no identifier."
        }
        let key: String = studentID.uuidString

        let enrollments: [CDStudentTrackEnrollmentEntity] = modelContext
            .safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
            .filter { $0.studentID == key }
            .filter { includeInactive || $0.isActive }
        guard !enrollments.isEmpty else {
            return "\(student.fullName) is not enrolled in any tracks."
        }

        let presentations: [CDLessonPresentation] = modelContext
            .safeFetch(CDFetchRequest(CDLessonPresentation.self))
            .filter { $0.studentID == key }

        var lines: [String] = ["\(student.fullName)'s tracks:"]
        for enrollment in enrollments {
            guard let track = enrollment.track else { continue }
            lines.append(trackLine(track, studentKey: key, presentations: presentations,
                                   isActive: enrollment.isActive, in: modelContext))
        }
        guard lines.count > 1 else {
            return "\(student.fullName)'s track enrollments have no tracks attached."
        }
        return lines.joined(separator: "\n")
    }

    private static func trackLine(
        _ track: CDTrackEntity, studentKey: String, presentations: [CDLessonPresentation],
        isActive: Bool, in modelContext: NSManagedObjectContext
    ) -> String {
        let id: String = track.id?.uuidString ?? "unknown"
        let total: Int = TrackProgressResolver.totalSteps(track: track)
        let done: Int = TrackProgressResolver.proficientCount(
            track: track, studentID: studentKey, lessonPresentations: presentations
        )
        let next: CDTrackStepEntity? = TrackProgressResolver.currentStep(
            track: track, studentID: studentKey, lessonPresentations: presentations
        )
        var details: [String] = ["\(done)/\(total) steps mastered"]
        if let next, let lessonName = lessonName(forTemplateID: next.lessonTemplateID, in: modelContext) {
            details.append("next: \(lessonName)")
        } else if next == nil && total > 0 {
            details.append("complete")
        }
        if !isActive {
            details.append("no longer active")
        }
        return "- [track id=\(id)] \(track.title) (\(details.joined(separator: "; ")))"
    }

    /// A track step points at a lesson template by id; naming it makes the
    /// "next step" line readable instead of printing a bare uuid.
    private static func lessonName(
        forTemplateID templateID: UUID?, in modelContext: NSManagedObjectContext
    ) -> String? {
        guard let templateID else { return nil }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", templateID as CVarArg)
        request.fetchLimit = 1
        return modelContext.safeFetch(request).first?.name
    }
}
