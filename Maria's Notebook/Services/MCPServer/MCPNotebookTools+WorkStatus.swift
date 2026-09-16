// MCPNotebookTools+WorkStatus.swift
// The status half of update_work: one verdict per child, logged through
// WorkLogService exactly as the Scheduled strip's menu logs it.
//
// Split from +WorkWrites for SwiftLint's file-length limit; the tool
// definition, schema and dispatcher stay there.

import CoreData
import Foundation

extension MCPNotebookTools {

    static func applyStatus(
        _ arguments: [String: JSONValue], to work: CDWorkModel, workID: UUID,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        let outcome = try completionOutcomeArgument(arguments, "outcome")
        // `outcome` alone used to mean "close it with this verdict"; it still does.
        let closingByOutcome = outcome.map { _ in WorkStatus.done.rawValue }
        guard let statusRaw = nonEmpty(arguments["status"]?.stringValue) ?? closingByOutcome else { return [] }
        guard WorkStatus(rawValue: statusRaw) != nil else {
            let allowed = WorkStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("status must be one of: \(allowed). Got \"\(statusRaw)\".")
        }
        let status = WorkStatusMigration.mergedStatus(statusRaw: statusRaw, outcomeRaw: outcome?.rawValue)

        // Which rows: every linked copy, or the copies the named children own.
        let named = try namedStudents(arguments, in: modelContext)
        let rows: [CDWorkModel]
        do {
            rows = try WorkLogTargets.resolve(work: work, students: named.map { Set($0.map(\.id)) }, in: modelContext)
        } catch {
            throw MCPToolError(error.localizedDescription)
        }

        // The same write the Scheduled strip makes: status, completion record,
        // the day's check-in completed, later ones skipped, the note filed.
        let note = nonEmpty(arguments["note"]?.stringValue)
        do {
            try WorkLogService.log(
                rows.map { WorkLogService.Entry(work: $0, status: status, note: note) },
                context: modelContext, saveImmediately: false
            )
        } catch {
            modelContext.rollback()
            throw MCPToolError("That status could not be logged: \(error.localizedDescription)")
        }

        let whom: String
        if let named {
            whom = "for " + named.map(\.name).joined(separator: ", ")
        } else if rows.count > 1 {
            whom = "for everyone (\(rows.count) linked copies)"
        } else {
            whom = ""
        }
        return [("logged as \(status.displayName) " + whom).trimmed()]
    }

    /// The `students` argument resolved to enrolled children, or nil when the
    /// call names none. Every name resolves before anything is written.
    static func namedStudents(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [(id: UUID, name: String)]? {
        guard let items = arguments["students"]?.arrayValue, !items.isEmpty else { return nil }
        return try items.map { item in
            guard let reference = nonEmpty(item.stringValue) else {
                throw MCPToolError("students must be a list of names.")
            }
            let student = try resolveStudentReference(reference, in: modelContext)
            guard let id = student.id else { throw MCPToolError("\(student.fullName) has no identifier.") }
            return (id: id, name: student.fullName)
        }
    }

    static func completionOutcomeArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> CompletionOutcome? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let outcome = CompletionOutcome(rawValue: raw) else {
            let allowed = CompletionOutcome.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return outcome
    }
}
