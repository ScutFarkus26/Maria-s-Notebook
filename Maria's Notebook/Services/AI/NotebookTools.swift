//
//  NotebookTools.swift
//  Maria's Notebook
//
//  FoundationModels tools that let the on-device model look things up in the
//  teacher's own data while answering chat questions ("ask your notebook").
//  Everything stays local: the model decides when to call a tool, the tool
//  queries the app's search index / Core Data store, and the results flow
//  back into the model's answer.
//

import Foundation
import CoreData
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

actor EvidenceSourceCollector {
    private var sourcesByID: [String: EvidenceReference] = [:]

    func record(_ reference: EvidenceReference) {
        sourcesByID[reference.id] = reference
    }

    func record(contentsOf references: [EvidenceReference]) {
        for reference in references {
            sourcesByID[reference.id] = reference
        }
    }

    func snapshot() -> [EvidenceReference] {
        sourcesByID.values.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    func consume() -> [EvidenceReference] {
        let snapshot = snapshot()
        sourcesByID.removeAll()
        return snapshot
    }
}

enum NotebookTools {
    /// The lookup toolset attached to on-device chat sessions.
    static func chatTools(sourceCollector: EvidenceSourceCollector? = nil) -> [any Tool] {
        [
            SearchNotebookTool(sourceCollector: sourceCollector),
            StudentNotesTool(sourceCollector: sourceCollector),
            StudentPresentationHistoryTool(sourceCollector: sourceCollector),
            PresentationWorkTool(sourceCollector: sourceCollector),
            MissingPresentationObservationsTool(sourceCollector: sourceCollector),
            SearchTeachingAlbumsTool()
        ]
    }
}

/// Keyword search across notes, lessons, students, todos, and work records.
struct SearchNotebookTool: Tool {
    let sourceCollector: EvidenceSourceCollector?
    let name = "searchNotebook"
    let description = "Search the teacher's notebook (observation notes, lessons, "
        + "students, todos, work records) by keyword. Returns the best matches with snippets."

    @Generable(description: "Notebook search arguments")
    struct Arguments {
        @Guide(description: "Keywords to search for — a student name, material, lesson, or topic")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query
        // The index can be purged under memory pressure — rebuild before searching
        // so a low-memory moment doesn't silently turn into "no results".
        await SearchIndexService.shared.ensureReady()
        let results = await MainActor.run {
            SearchIndexService.shared.search(query: query, limit: 8)
        }
        guard !results.isEmpty else {
            return "No notebook entries matched \"\(query)\"."
        }
        if let sourceCollector {
            for result in results {
                await sourceCollector.record(result.evidenceReference)
            }
        }
        let lines = results.enumerated().map { index, result in
            let date = result.date.map { DateFormatters.mediumDate.string(from: $0) } ?? "Undated"
            return "- [S\(index + 1)] [\(result.entityType.rawValue) id=\(result.id.uuidString)] \(date) — \(result.title): \(result.snippet)"
        }
        return lines.joined(separator: "\n")
    }
}

/// A student's recent observation notes with dates and full text.
struct StudentNotesTool: Tool {
    let sourceCollector: EvidenceSourceCollector?
    let name = "recentStudentNotes"
    let description = "Get a student's observation notes from the last N days, with dates "
        + "and full text. Use when asked about a specific student's recent work or behavior."

    @Generable(description: "Recent student notes arguments")
    struct Arguments {
        @Guide(description: "The student's first name or full name")
        var studentName: String

        @Guide(description: "How many days back to look (1-120; use 30 if unsure)")
        var daysBack: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let name = arguments.studentName
        let days = min(max(arguments.daysBack, 1), 120)
        let result = await MainActor.run {
            Self.fetchNotes(studentName: name, daysBack: days)
        }
        if let sourceCollector {
            await sourceCollector.record(contentsOf: result.sources)
        }
        return result.text
    }

    @MainActor
    private static func fetchNotes(
        studentName: String,
        daysBack: Int
    ) -> (text: String, sources: [EvidenceReference]) {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext

        // Resolve the student by (diacritic-insensitive) name.
        let token = studentName.folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let studentRequest = CDFetchRequest(CDStudent.self)
        let students = context.safeFetch(studentRequest)
        let matches = students.filter { s in
            let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nick = (s.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return token == first || token == "\(first) \(last)" || (!nick.isEmpty && token == nick)
        }
        guard !matches.isEmpty else {
            return ("No student named \"\(studentName)\" found in this classroom.", [])
        }
        if matches.count > 1 {
            let names = matches.map(\.fullName).sorted().joined(separator: ", ")
            return ("More than one student matches \"\(studentName)\": \(names). Ask the guide which student they mean.", [])
        }
        guard let student = matches.first, let studentID = student.id else {
            return ("No student named \"\(studentName)\" found in this classroom.", [])
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date.distantPast
        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(format: "createdAt >= %@", cutoff as NSDate)
        noteRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let notes = context.safeFetch(noteRequest)

        let matching = notes.filter { note in
            switch note.scope {
            case .all:
                return false // classroom-wide notes aren't about this student specifically
            case .student(let id):
                return id == studentID
            case .students(let ids):
                return ids.contains(studentID)
            }
        }
        guard !matching.isEmpty else {
            return ("No notes about \(student.firstName) in the last \(daysBack) days.", [])
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let selected = Array(matching.prefix(20))
        let lines = selected.map { note -> String in
            let date = note.createdAt.map { formatter.string(from: $0) } ?? "Undated"
            let tags = note.tagsArray.isEmpty ? "" : " [\(note.tagsArray.joined(separator: ", "))]"
            return "[note id=\(note.id?.uuidString ?? "unknown")] \(date)\(tags): \(note.body)"
        }
        let sources = selected.compactMap { note -> EvidenceReference? in
            guard let id = note.id else { return nil }
            return EvidenceReference(
                entityKind: .note,
                entityID: id,
                date: note.createdAt,
                title: "Observation about \(student.fullName)",
                excerpt: String(note.body.prefix(180))
            )
        }
        return (
            "Notes about \(student.firstName) (last \(daysBack) days):\n" + lines.joined(separator: "\n"),
            sources
        )
    }
}

private struct NotebookToolResult: Sendable {
    let text: String
    let sources: [EvidenceReference]
}

/// Exact presentation history for one unambiguously resolved student.
struct StudentPresentationHistoryTool: Tool {
    let sourceCollector: EvidenceSourceCollector?
    let name = "studentPresentationHistory"
    let description = "Look up dated lesson presentations for one student. Use this instead of inferring lesson history from work."

    @Generable(description: "Student presentation-history arguments")
    struct Arguments {
        @Guide(description: "The student's first or full name")
        var studentName: String
        @Guide(description: "Maximum presentations to return, from 1 through 20")
        var limit: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let result = await MainActor.run {
            Self.fetch(studentName: arguments.studentName, limit: min(max(arguments.limit, 1), 20))
        }
        if let sourceCollector {
            await sourceCollector.record(contentsOf: result.sources)
        }
        return result.text
    }

    @MainActor
    private static func fetch(studentName: String, limit: Int) -> NotebookToolResult {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        switch NotebookToolStudentResolver.resolve(studentName, in: context) {
        case .failure(let message):
            return NotebookToolResult(text: message, sources: [])
        case .success(let student):
            guard let studentID = student.id else {
                return NotebookToolResult(text: "That student record has no identifier.", sources: [])
            }
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "stateRaw == %@", LessonAssignmentState.presented.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)]
            let assignments = context.safeFetch(request)
                .filter { $0.studentUUIDs.contains(studentID) }
                .prefix(limit)
            guard !assignments.isEmpty else {
                return NotebookToolResult(text: "No presentations are recorded for \(student.fullName).", sources: [])
            }

            var sources: [EvidenceReference] = []
            let lines = assignments.enumerated().compactMap { index, assignment -> String? in
                guard let id = assignment.id else { return nil }
                let snapshotTitle = assignment.lessonTitleSnapshot?.trimmed() ?? ""
                let title = snapshotTitle.isEmpty ? (assignment.lesson?.name ?? "Lesson") : snapshotTitle
                let date = assignment.presentedAt.map { DateFormatters.mediumDate.string(from: $0) } ?? "Undated"
                sources.append(EvidenceReference(
                    entityKind: .presentation,
                    entityID: id,
                    date: assignment.presentedAt,
                    title: title,
                    excerpt: "Presented to \(student.fullName) on \(date)."
                ))
                let notes = ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? [])
                    .filter { $0.scope.applies(to: studentID) && !$0.body.trimmed().isEmpty }
                for note in notes.prefix(2) {
                    guard let noteID = note.id else { continue }
                    sources.append(EvidenceReference(
                        entityKind: .note,
                        entityID: noteID,
                        date: note.createdAt,
                        title: "Observation after \(title)",
                        excerpt: String(note.body.prefix(180))
                    ))
                }
                let noteText = notes.isEmpty ? "no linked observation" : "\(notes.count) linked observation(s)"
                return "- [P\(index + 1)] [presentation id=\(id.uuidString)] \(date) — \(title) (\(noteText))"
            }
            return NotebookToolResult(
                text: "Presentations for \(student.fullName):\n" + lines.joined(separator: "\n"),
                sources: sources
            )
        }
    }
}

/// Work records linked to one exact presentation.
struct PresentationWorkTool: Tool {
    let sourceCollector: EvidenceSourceCollector?
    let name = "workForPresentation"
    let description = "Look up work explicitly linked to a presentation ID returned by another notebook tool."

    @Generable(description: "Presentation work lookup arguments")
    struct Arguments {
        @Guide(description: "The exact presentation UUID")
        var presentationID: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let presentationID = UUID(uuidString: arguments.presentationID) else {
            return "The presentation ID was not a valid UUID."
        }
        let result = await MainActor.run { Self.fetch(presentationID: presentationID) }
        if let sourceCollector {
            await sourceCollector.record(contentsOf: result.sources)
        }
        return result.text
    }

    @MainActor
    private static func fetch(presentationID: UUID) -> NotebookToolResult {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]
        let work = context.safeFetch(request)
        guard !work.isEmpty else {
            return NotebookToolResult(text: "No work is linked to that presentation.", sources: [])
        }
        let sources = work.compactMap { item -> EvidenceReference? in
            guard let id = item.id else { return nil }
            return EvidenceReference(
                entityKind: .work,
                entityID: id,
                date: item.createdAt,
                title: item.title,
                excerpt: "Status: \(item.status.displayName)"
            )
        }
        let lines = work.enumerated().map { index, item in
            "- [W\(index + 1)] [work id=\(item.id?.uuidString ?? "unknown")] \(item.title) — \(item.status.displayName)"
        }
        return NotebookToolResult(text: lines.joined(separator: "\n"), sources: sources)
    }
}

/// Deterministic coverage check for presentations lacking a linked observation.
struct MissingPresentationObservationsTool: Tool {
    let sourceCollector: EvidenceSourceCollector?
    let name = "presentationsMissingObservations"
    let description = "Find presented lessons that have no linked observation. This reports missing records and never judges readiness."

    @Generable(description: "Missing presentation-observation arguments")
    struct Arguments {
        @Guide(description: "How many days back to check, from 1 through 120")
        var daysBack: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let days = min(max(arguments.daysBack, 1), 120)
        let result = await MainActor.run {
            let context = AppBootstrapping.getSharedCoreDataStack().viewContext
            let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
            return PresentationObservationCoverageService.missingObservationReferences(
                in: context,
                from: start,
                through: Date()
            )
        }
        if let sourceCollector {
            await sourceCollector.record(contentsOf: result)
        }
        guard !result.isEmpty else {
            return "Every presentation in the last \(days) days has a linked observation."
        }
        return result.enumerated().map { index, reference in
            let date = reference.date.map { DateFormatters.mediumDate.string(from: $0) } ?? "Undated"
            return "- [M\(index + 1)] [presentation id=\(reference.entityID.uuidString)] \(date) — \(reference.title)"
        }.joined(separator: "\n")
    }
}

@MainActor
private enum NotebookToolStudentResolver {
    enum Resolution {
        case success(CDStudent)
        case failure(String)
    }

    static func resolve(_ name: String, in context: NSManagedObjectContext) -> Resolution {
        let token = name.folding(options: .diacriticInsensitive, locale: .current)
            .trimmed().lowercased()
        let matches = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { student in
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let full = student.fullName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nickname = (student.nickname ?? "")
                .folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return token == first || token == full || (!nickname.isEmpty && token == nickname)
        }
        guard !matches.isEmpty else {
            return .failure("No student named \"\(name)\" was found.")
        }
        guard matches.count == 1, let student = matches.first else {
            return .failure(
                "More than one student matches \"\(name)\": \(matches.map(\.fullName).sorted().joined(separator: ", ")). Ask which student the guide means."
            )
        }
        return .success(student)
    }
}

private extension SearchResult {
    var evidenceReference: EvidenceReference {
        let kind: EvidenceEntityKind = switch entityType {
        case .note: .note
        case .lesson: .lesson
        case .student: .student
        case .todo: .todo
        case .work: .work
        }
        return EvidenceReference(
            entityKind: kind,
            entityID: id,
            date: date,
            title: title,
            excerpt: snippet
        )
    }
}

/// Full-text search of the guide's own Montessori teaching-album PDFs.
///
/// Album pages have no UUID, so this tool doesn't feed the evidence collector
/// the way the notebook tools do; its citations are inline in the returned
/// text instead of appearing as Sources pills.
struct SearchTeachingAlbumsTool: Tool {
    let name = "searchTeachingAlbums"
    let description = "Search the guide's Montessori teaching-album PDFs by meaning and keyword. "
        + "Use for questions about how to present a lesson, what materials it needs, "
        + "or what the albums say about a topic."

    @Generable(description: "Teaching-album search arguments")
    struct Arguments {
        @Guide(description: "Keywords or a question — a material, lesson name, or topic")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query
        let hits = await AlbumCorpusLookup.search(query: query, limit: 6)
        guard !hits.isEmpty else {
            return await AlbumCorpusLookup.emptyResultMessage(for: query)
        }
        return hits.map(\.citationLine).joined(separator: "\n")
    }
}

#endif
