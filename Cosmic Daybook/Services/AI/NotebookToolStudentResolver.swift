//
//  NotebookToolStudentResolver.swift
//  Cosmic Daybook
//
//  Finds the one child Ask AI's notebook tools were asked about.
//

import CoreData
import Foundation

@MainActor
enum NotebookToolStudentResolver {
    enum Resolution {
        case success(CDStudent)
        case failure(String)
    }

    static func resolve(_ name: String, in context: NSManagedObjectContext) -> Resolution {
        resolve(name, among: context.safeFetch(CDFetchRequest(CDStudent.self)))
    }

    /// A full name or a short name ("Etty D", with or without a period: the
    /// form the app uses when two children share a first name) settles a
    /// first name two children share; a first name or nickname is tried only
    /// when no whole name matches. Diacritic- and case-insensitive, the same
    /// rule as the MCP server's `resolveStudent` (bug hunt 2026-10-11 #49).
    static func resolve(_ name: String, among students: [CDStudent]) -> Resolution {
        var token = name.folded()
        if token.hasSuffix(".") { token.removeLast() }
        guard !token.isEmpty else {
            return .failure("Say which student you mean.")
        }
        let byWholeName = students.filter { student in
            token == student.fullName.folded() || token == student.shortName.folded()
        }
        let matches = byWholeName.isEmpty
            ? students.filter { student in
                let nickname = (student.nickname ?? "").folded()
                return token == student.firstName.folded() || (!nickname.isEmpty && token == nickname)
            }
            : byWholeName
        guard !matches.isEmpty else {
            return .failure("No student named \"\(name)\" was found.")
        }
        guard matches.count == 1, let student = matches.first else {
            let names = matches.map { "\($0.fullName) (\($0.shortName))" }.sorted().joined(separator: ", ")
            return .failure(
                "More than one student matches \"\(name)\": \(names). "
                    + "Ask which student the guide means, then use that child's short name."
            )
        }
        return .success(student)
    }
}
