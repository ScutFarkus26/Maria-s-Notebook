//
//  MCPNotebookTools+Reference.swift
//  Cosmic Daybook
//
//  The material a guide consults rather than edits day to day: written
//  procedures, the story shelf, and where each child stands on their sequence
//  tracks. Community topics moved to their own file when they gained a writer.
//
//  Track progress goes through TrackProgressResolver, the same helper the
//  progression screens use, so "mastered" means the same thing everywhere, and
//  enrollments fold by track title the way StudentHistoryTab folds them — the
//  store still holds twin track definitions from a migration that ran twice.
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
            annotations: .readOnly,
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

        let standings: [TrackStanding] = foldedStandings(
            for: enrollments, studentKey: key, presentations: presentations, in: modelContext
        )
        guard !standings.isEmpty else {
            return "\(student.fullName)'s track enrollments have no tracks attached."
        }
        let lines: [String] = standings.map { trackLine($0, in: modelContext) }
        return (["\(student.fullName)'s tracks:"] + lines).joined(separator: "\n")
    }

    /// Where one enrollment leaves a child on one track.
    ///
    /// The store holds duplicate track definitions — a migration that ran twice
    /// left twin rows under the same title, and some twins kept none of the
    /// steps. A child enrolled on both twins used to get two lines for one
    /// track, so the standings are folded by title the way the history tab
    /// folds its enrollments (`StudentHistoryTab.finishedEnrollments`).
    private struct TrackStanding {
        let track: CDTrackEntity
        let total: Int
        let done: Int
        let next: CDTrackStep?
        let isActive: Bool

        /// The fuller record of a title wins: more steps mastered, then more
        /// steps defined, then a live enrollment over a finished one.
        func outranks(_ other: TrackStanding) -> Bool {
            if done != other.done { return done > other.done }
            if total != other.total { return total > other.total }
            return isActive && !other.isActive
        }
    }

    /// One standing per folded title, in the order the titles first appear.
    /// Stepless shells are dropped outright: "0/0 steps mastered" is a duplicate
    /// definition showing through, not a fact about the child.
    private static func foldedStandings(
        for enrollments: [CDStudentTrackEnrollmentEntity], studentKey: String,
        presentations: [CDLessonPresentation], in modelContext: NSManagedObjectContext
    ) -> [TrackStanding] {
        var best: [String: TrackStanding] = [:]
        var order: [String] = []
        for enrollment in enrollments {
            guard let track = resolveTrack(for: enrollment, in: modelContext) else { continue }
            let total: Int = TrackProgressResolver.totalSteps(track: track)
            guard total > 0 else { continue }
            let standing = TrackStanding(
                track: track,
                total: total,
                done: TrackProgressResolver.proficientCount(
                    track: track, studentID: studentKey, lessonPresentations: presentations
                ),
                next: TrackProgressResolver.currentStep(
                    track: track, studentID: studentKey, lessonPresentations: presentations
                ),
                isActive: enrollment.isActive
            )
            let folded: String = LessonRepository.foldedName(track.title)
            guard let existing = best[folded] else {
                best[folded] = standing
                order.append(folded)
                continue
            }
            if standing.outranks(existing) { best[folded] = standing }
        }
        return order.compactMap { best[$0] }
    }

    /// An enrollment carries both a `track` relationship and a `trackID` string,
    /// and the relationship can arrive empty while the id is sound. Fall back to
    /// the id before dropping the row, or a real enrolment goes missing.
    private static func resolveTrack(
        for enrollment: CDStudentTrackEnrollmentEntity, in modelContext: NSManagedObjectContext
    ) -> CDTrackEntity? {
        if let track = enrollment.track { return track }
        guard let trackID = UUID(uuidString: enrollment.trackID.trimmed()) else { return nil }
        let request = CDFetchRequest(CDTrackEntity.self)
        request.predicate = NSPredicate(format: "id == %@", trackID as CVarArg)
        request.fetchLimit = 1
        return modelContext.safeFetch(request).first
    }

    private static func trackLine(
        _ standing: TrackStanding, in modelContext: NSManagedObjectContext
    ) -> String {
        let id: String = standing.track.id?.uuidString ?? "unknown"
        var details: [String] = ["\(standing.done)/\(standing.total) steps mastered"]
        if let next = standing.next,
           let lessonName = lessonName(forTemplateID: next.lessonTemplateID, in: modelContext) {
            details.append("next: \(lessonName)")
        } else if standing.next == nil {
            details.append("complete")
        }
        if !standing.isActive {
            details.append("no longer active")
        }
        return "- [track id=\(id)] \(standing.track.title) (\(details.joined(separator: "; ")))"
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
