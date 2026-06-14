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

enum NotebookTools {
    /// The lookup toolset attached to on-device chat sessions.
    static func chatTools() -> [any Tool] {
        [SearchNotebookTool(), StudentNotesTool()]
    }
}

/// Keyword search across notes, lessons, students, todos, and work records.
struct SearchNotebookTool: Tool {
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
        let results = await MainActor.run {
            SearchIndexService.shared.search(query: query, limit: 8)
        }
        guard !results.isEmpty else {
            return "No notebook entries matched \"\(query)\"."
        }
        let lines = results.map { result in
            "- [\(result.entityType.rawValue)] \(result.title): \(result.snippet)"
        }
        return lines.joined(separator: "\n")
    }
}

/// A student's recent observation notes with dates and full text.
struct StudentNotesTool: Tool {
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
        return await MainActor.run {
            Self.fetchNotes(studentName: name, daysBack: days)
        }
    }

    @MainActor
    private static func fetchNotes(studentName: String, daysBack: Int) -> String {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext

        // Resolve the student by (diacritic-insensitive) name.
        let token = studentName.folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let studentRequest = CDFetchRequest(CDStudent.self)
        let students = context.safeFetch(studentRequest)
        guard let student = students.first(where: { s in
            let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nick = (s.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return token == first || token == "\(first) \(last)" || (!nick.isEmpty && token == nick)
        }), let studentID = student.id else {
            return "No student named \"\(studentName)\" found in this classroom."
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
            return "No notes about \(student.firstName) in the last \(daysBack) days."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let lines = matching.prefix(20).map { note -> String in
            let date = note.createdAt.map { formatter.string(from: $0) } ?? "Undated"
            let tags = note.tagsArray.isEmpty ? "" : " [\(note.tagsArray.joined(separator: ", "))]"
            return "\(date)\(tags): \(note.body)"
        }
        return "Notes about \(student.firstName) (last \(daysBack) days):\n" + lines.joined(separator: "\n")
    }
}

#endif
