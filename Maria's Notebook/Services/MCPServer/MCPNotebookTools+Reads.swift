//
//  MCPNotebookTools+Reads.swift
//  Maria's Notebook
//
//  Read-only MCP tools. Query logic and output conventions mirror the
//  on-device NotebookTools (Services/AI/NotebookTools.swift) so both AI
//  surfaces describe the classroom the same way: entities are cited as
//  "[kind id=<uuid>]" so follow-up tools can chain on the identifiers.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    // MARK: - Roster

    static func listStudentsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_students",
            title: "List Students",
            description: "List the students in the classroom with their ids, levels, ages, "
                + "and enrollment dates. Former students (withdrawn or transferred) are "
                + "excluded unless requested.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "include_withdrawn": [
                        "type": "boolean",
                        "description": "Also list former students — withdrawn or transferred (default false)"
                    ]
                ]
            ],
            handler: { arguments in
                let includeWithdrawn = arguments["include_withdrawn"]?.boolValue ?? false
                let students = DataQueryService(context: context())
                    .fetchAllStudents(excludeTest: true, excludeWithdrawn: !includeWithdrawn)
                    .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
                guard !students.isEmpty else { return "No students are enrolled." }
                let lines = students.map { student -> String in
                    var details = [student.level.rawValue.lowercased()]
                    if let birthday = student.birthday {
                        let age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
                        details.append("age \(age)")
                    }
                    if let started = student.dateStarted {
                        details.append("started \(dayString(started))")
                    }
                    if !student.isEnrolled {
                        details.append(student.enrollmentStatusRaw)
                    }
                    let nickname = student.nickname.map { " \"\($0)\"" } ?? ""
                    let id = student.id?.uuidString ?? "unknown"
                    return "- [student id=\(id)] \(student.fullName)\(nickname) (\(details.joined(separator: ", ")))"
                }
                return "\(students.count) student(s):\n" + lines.joined(separator: "\n")
            }
        )
    }

    // MARK: - Search

    static func searchNotebookTool() -> MCPToolDefinition {
        MCPToolDefinition(
            name: "search_notebook",
            title: "Search Notebook",
            description: "Keyword search across the whole notebook: observation notes, lessons, "
                + "students, todos, and work records. Returns the best matches with snippets.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Keywords — a student name, material, lesson, or topic"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum results, 1-25 (default 8)"
                    ]
                ],
                "required": ["query"]
            ],
            handler: { arguments in
                let query = try requireString(arguments, "query")
                let limit = intArgument(arguments, "limit", default: 8, range: 1...25)
                // The index can be purged under memory pressure — rebuild first so
                // a low-memory moment doesn't silently turn into "no results".
                await SearchIndexService.shared.ensureReady()
                let results = SearchIndexService.shared.search(query: query, limit: limit)
                guard !results.isEmpty else {
                    return "No notebook entries matched \"\(query)\"."
                }
                let lines = results.map { result in
                    "- [\(result.entityType.rawValue) id=\(result.id.uuidString)] \(dayString(result.date)) — "
                        + "\(result.title): \(result.snippet)"
                }
                return lines.joined(separator: "\n")
            }
        )
    }

    // MARK: - Student Observations

    static func studentObservationsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_observations",
            title: "Student Observations",
            description: "Get one student's observation notes from the last N days, "
                + "with dates, tags, and full text.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "days_back": [
                        "type": "integer",
                        "description": "How many days back to look, 1-120 (default 30)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                let name = try requireString(arguments, "student_name")
                let daysBack = intArgument(arguments, "days_back", default: 30, range: 1...120)
                return try fetchStudentObservations(name: name, daysBack: daysBack, in: context())
            }
        )
    }

    @MainActor
    private static func fetchStudentObservations(
        name: String, daysBack: Int, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudent(named: name, in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? .distantPast
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "createdAt >= %@", cutoff as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let notes = modelContext.safeFetch(request)
            .filter { note in
                // Classroom-wide notes aren't about this student specifically.
                switch note.scope {
                case .all: return false
                case .student(let id): return id == studentID
                case .students(let ids): return ids.contains(studentID)
                }
            }
            .prefix(20)
        guard !notes.isEmpty else {
            return "No notes about \(student.firstName) in the last \(daysBack) days."
        }

        let lines = notes.map { note -> String in
            let tags = note.tagsArray.isEmpty ? "" : " [\(note.tagsArray.joined(separator: ", "))]"
            let id = note.id?.uuidString ?? "unknown"
            return "- [note id=\(id)] \(dayString(note.createdAt))\(tags): \(note.body)"
        }
        return "Notes about \(student.firstName) (last \(daysBack) days):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Presentation History

    static func studentPresentationHistoryTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_presentation_history",
            title: "Student Presentation History",
            description: "Dated lesson presentations for one student, newest first. "
                + "Use this instead of inferring lesson history from work records.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum presentations to return, 1-20 (default 10)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                let name = try requireString(arguments, "student_name")
                let limit = intArgument(arguments, "limit", default: 10, range: 1...20)
                return try fetchPresentationHistory(name: name, limit: limit, in: context())
            }
        )
    }

    @MainActor
    private static func fetchPresentationHistory(
        name: String, limit: Int, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudent(named: name, in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "stateRaw == %@", LessonAssignmentState.presented.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)
        ]
        let assignments = modelContext.safeFetch(request)
            .filter { $0.studentUUIDs.contains(studentID) }
            .prefix(limit)
        guard !assignments.isEmpty else {
            return "No presentations are recorded for \(student.fullName)."
        }

        let lines = assignments.compactMap { assignment -> String? in
            guard let id = assignment.id else { return nil }
            let snapshotTitle = assignment.lessonTitleSnapshot?.trimmed() ?? ""
            let title = snapshotTitle.isEmpty ? (assignment.lesson?.name ?? "Lesson") : snapshotTitle
            let notes = ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? [])
                .filter { $0.scope.applies(to: studentID) && !$0.body.trimmed().isEmpty }
            let noteText = notes.isEmpty ? "no linked observation" : "\(notes.count) linked observation(s)"
            return "- [presentation id=\(id.uuidString)] \(dayString(assignment.presentedAt)) — "
                + "\(title) (\(noteText))"
        }
        return "Presentations for \(student.fullName):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Observation Coverage

    static func presentationsMissingObservationsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "presentations_missing_observations",
            title: "Presentations Missing Observations",
            description: "Find presented lessons with no linked observation in the last N days. "
                + "Reports missing records only; it never judges readiness.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "days_back": [
                        "type": "integer",
                        "description": "How many days back to check, 1-120 (default 30)"
                    ]
                ]
            ],
            handler: { arguments in
                let daysBack = intArgument(arguments, "days_back", default: 30, range: 1...120)
                let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? .distantPast
                let references = PresentationObservationCoverageService.missingObservationReferences(
                    in: context(),
                    from: start,
                    through: Date()
                )
                guard !references.isEmpty else {
                    return "Every presentation in the last \(daysBack) days has a linked observation."
                }
                return references.map { reference in
                    "- [presentation id=\(reference.entityID.uuidString)] \(dayString(reference.date)) — "
                        + reference.title
                }.joined(separator: "\n")
            }
        )
    }

    // MARK: - Classroom Snapshot

    static func classroomSnapshotTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "classroom_snapshot",
            title: "Classroom Snapshot",
            description: "A prose overview of the classroom right now: roster, recent activity, "
                + "and open threads. A good first call when orienting to the classroom.",
            inputSchema: ["type": "object", "properties": [:]],
            handler: { _ in
                ChatContextAssembler(context: context()).buildClassroomSnapshot()
            }
        )
    }
}

// MARK: - Teaching Albums

extension MCPNotebookTools {
    /// Full-text + semantic search of the guide's teaching-album PDFs.
    /// Wording and citation format match the on-device `searchTeachingAlbums`
    /// chat tool — the two surfaces are meant to stay interchangeable.
    static func searchAlbumsTool() -> MCPToolDefinition {
        MCPToolDefinition(
            name: "search_albums",
            title: "Search Teaching Albums",
            description: "Search the guide's Montessori teaching-album PDFs by meaning and "
                + "keyword. Use for how a lesson is presented, what materials it needs, or what "
                + "the albums say about a topic. Each result is cited as "
                + "[albumPage album=\"<file>\" page=<n>]; pass those to get_album_page for the "
                + "full page.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Keywords or a question — a material, lesson name, or topic"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum results, 1-25 (default 8)"
                    ]
                ],
                "required": ["query"]
            ],
            handler: { arguments in
                let query = try requireString(arguments, "query")
                let limit = intArgument(arguments, "limit", default: 8, range: 1...25)
                let hits = await AlbumCorpusLookup.search(query: query, limit: limit)
                guard !hits.isEmpty else {
                    return await AlbumCorpusLookup.emptyResultMessage(for: query)
                }
                return hits.map(\.citationLine).joined(separator: "\n")
            }
        )
    }

    /// The full text of one album page, so a citation from search_albums can
    /// be followed up without re-searching.
    static func albumPageTool() -> MCPToolDefinition {
        MCPToolDefinition(
            name: "get_album_page",
            title: "Read Album Page",
            description: "Return the full text of one page of a teaching album. Use the album "
                + "filename and page number from a [albumPage …] citation.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "album": [
                        "type": "string",
                        "description": "Album filename, e.g. \"Biology Album.pdf\""
                    ],
                    "page": [
                        "type": "integer",
                        "description": "Page number as printed in the citation (1-based)"
                    ]
                ],
                "required": ["album", "page"]
            ],
            handler: { arguments in
                let album = try requireString(arguments, "album")
                let page = intArgument(arguments, "page", default: 1, range: 1...10_000)
                guard let text = await AlbumCorpusLookup.page(album: album, page: page),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return "No text found for page \(page) of \"\(album)\". Check the album "
                        + "filename and page number from the citation."
                }
                return text
            }
        )
    }
}
