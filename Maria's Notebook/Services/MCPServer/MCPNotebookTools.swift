//
//  MCPNotebookTools.swift
//  Maria's Notebook
//
//  The toolset the MCP server exposes to Claude Desktop: read tools that
//  mirror the on-device NotebookTools lookups, plus a sanctioned
//  observation-capture write that follows LogObservationIntent.
//
//  All handlers run on the main actor and read through the app's shared
//  Core Data stack, the same entry point the Siri intents use.
//

import CoreData
import Foundation

/// Supplies the managed object context tools should query. Injectable so
/// tests can point the tools at an in-memory stack.
typealias MCPContextProvider = @MainActor @Sendable () -> NSManagedObjectContext

enum MCPNotebookTools {
    /// Builds the full toolset backed by the given context provider.
    @MainActor
    static func makeTools(
        context: @escaping MCPContextProvider = { AppBootstrapping.getSharedCoreDataStack().viewContext }
    ) -> [MCPToolDefinition] {
        [
            listStudentsTool(context: context),
            searchNotebookTool(),
            studentObservationsTool(context: context),
            studentPresentationHistoryTool(context: context),
            presentationsMissingObservationsTool(context: context),
            classroomSnapshotTool(context: context),
            searchAlbumsTool(),
            albumPageTool(),
            createObservationTool(context: context),
            updateStudentTool(context: context),
            updateObservationTool(context: context)
        ]
    }
}

// MARK: - Shared Helpers

extension MCPNotebookTools {
    /// Formats dates for tool output; the server's instructions promise ISO 8601.
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func dayString(_ date: Date?) -> String {
        date.map { isoDay.string(from: $0) } ?? "undated"
    }

    /// Resolves a student by first name, full name, or nickname
    /// (diacritic- and case-insensitive), mirroring NotebookTools'
    /// resolver. Ambiguity and misses throw tool errors the model can
    /// relay to the teacher.
    @MainActor
    static func resolveStudent(named name: String, in context: NSManagedObjectContext) throws -> CDStudent {
        let token = name.folding(options: .diacriticInsensitive, locale: .current)
            .trimmed().lowercased()
        guard !token.isEmpty else {
            throw MCPToolError("A student name is required.")
        }
        let matches = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { student in
            let first = student.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let full = student.fullName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nickname = (student.nickname ?? "")
                .folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return token == first || token == full || (!nickname.isEmpty && token == nickname)
        }
        guard !matches.isEmpty else {
            throw MCPToolError("No student named \"\(name)\" was found.")
        }
        guard matches.count == 1, let student = matches.first else {
            let names = matches.map(\.fullName).sorted().joined(separator: ", ")
            throw MCPToolError(
                "More than one student matches \"\(name)\": \(names). Ask which student the guide means."
            )
        }
        return student
    }

    // MARK: Argument Extraction

    static func requireString(_ arguments: [String: JSONValue], _ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue?.trimmed(), !value.isEmpty else {
            throw MCPToolError("Missing required argument: \(key)")
        }
        return value
    }

    static func intArgument(_ arguments: [String: JSONValue], _ key: String,
                            default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let value = arguments[key]?.intValue ?? defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func stringArrayArgument(_ arguments: [String: JSONValue], _ key: String) -> [String] {
        (arguments[key]?.arrayValue ?? []).compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
    }
}
