//
//  MCPNotebookTools+Classroom.swift
//  Maria's Notebook
//
//  Going Outs: where the class has proposed to go, when, with whom, and
//  whether the permission slips are back.
//
//  The job roster lives in MCPNotebookTools+Jobs.swift and the supply shelf in
//  MCPNotebookTools+Supplies.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Going Out

    static func listGoingOutsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_going_outs",
            title: "List Going Outs",
            description: "Going Outs the class has proposed, planned, approved or completed — "
                + "with destination, date, who is going, and where permissions stand.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "status": [
                        "type": "string",
                        "enum": ["proposed", "planning", "approved", "completed", "cancelled"],
                        "description": "Only Going Outs in this state (default: all)"
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "Only Going Outs this student is on"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let status = try goingOutStatusArgument(arguments, "status")
                let student = try nonEmpty(arguments["student_name"]?.stringValue)
                    .map { try resolveStudentReference($0, in: modelContext) }
                return describeGoingOuts(status: status, student: student, in: modelContext)
            }
        )
    }

    private static func describeGoingOuts(
        status: GoingOutStatus?, student: CDStudent?, in modelContext: NSManagedObjectContext
    ) -> String {
        let matched = modelContext.safeFetch(CDFetchRequest(CDGoingOut.self))
            .filter { status == nil || $0.status == status }
            .filter { goingOut in
                guard let studentID = student?.id else { return true }
                return goingOut.studentIDsArray.contains(studentID.uuidString)
            }
            .sorted { lhs, rhs in
                let leftDate = lhs.actualDate ?? lhs.proposedDate ?? .distantFuture
                let rightDate = rhs.actualDate ?? rhs.proposedDate ?? .distantFuture
                return leftDate > rightDate
            }

        guard !matched.isEmpty else { return "No Going Outs match that." }

        let names = studentNameIndex(in: modelContext)
        let lines = matched.map { goingOut -> String in
            let id = goingOut.id?.uuidString ?? "unknown"
            var details = [goingOut.status.rawValue]
            if let date = goingOut.actualDate ?? goingOut.proposedDate {
                details.append(dayString(date))
            }
            if goingOut.permissionStatus != .approved {
                details.append("permissions \(goingOut.permissionStatus.rawValue)")
            }
            let who = goingOut.studentIDsArray.compactMap { names[$0] }
            if !who.isEmpty {
                details.append(who.joined(separator: ", "))
            }
            let place = nonEmpty(goingOut.destination).map { " → \($0)" } ?? ""
            return "- [goingOut id=\(id)] \(goingOut.title)\(place) (\(details.joined(separator: "; ")))"
        }
        return "\(matched.count) Going Out(s):\n" + lines.joined(separator: "\n")
    }

    static func updateGoingOutTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_going_out",
            title: "Plan Or Update A Going Out",
            description: "Propose a Going Out, or move an existing one along: its date, status, "
                + "permission state, supervisor, notes, or who is going. Pass going_out_id to "
                + "update; pass title to propose a new one.",
            inputSchema: updateGoingOutSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateGoingOut(arguments: arguments, in: context())
            }
        )
    }

    private static let updateGoingOutSchema: JSONValue = [
        "type": "object",
        "properties": [
            "going_out_id": [
                "type": "string",
                "description": "The Going Out to update. Omit to propose a new one."
            ],
            "title": ["type": "string", "description": "What it is called"],
            "destination": ["type": "string", "description": "Where the class is going"],
            "purpose": ["type": "string", "description": "Why — the work it serves"],
            "proposed_date": ["type": "string", "description": "The hoped-for day, YYYY-MM-DD"],
            "actual_date": ["type": "string", "description": "The day it happened, YYYY-MM-DD"],
            "status": [
                "type": "string",
                "enum": ["proposed", "planning", "approved", "completed", "cancelled"],
                "description": "Where the plan stands"
            ],
            "permission_status": [
                "type": "string",
                "enum": ["pending", "sent", "approved", "denied"],
                "description": "Where the permission slips stand"
            ],
            "supervisor_name": ["type": "string", "description": "The adult going along"],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Replace the students going"
            ],
            "notes": ["type": "string", "description": "Anything else worth recording"]
        ]
    ]

    private static func updateGoingOut(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let goingOut: CDGoingOut
        let verb: String
        if let reference = nonEmpty(arguments["going_out_id"]?.stringValue) {
            goingOut = try resolveGoingOut(reference, in: modelContext)
            verb = "Updated"
        } else {
            guard nonEmpty(arguments["title"]?.stringValue) != nil else {
                throw MCPToolError("Proposing a Going Out needs a title.")
            }
            goingOut = CDGoingOut(context: modelContext)
            goingOut.id = UUID()
            goingOut.createdAt = Date()
            verb = "Proposed"
        }

        var changes: [String] = []
        changes += applyGoingOutText(arguments, to: goingOut)
        changes += try applyGoingOutDates(arguments, to: goingOut)
        changes += try applyGoingOutStatus(arguments, to: goingOut)
        changes += try applyGoingOutStudents(arguments, to: goingOut, in: modelContext)
        goingOut.modifiedAt = Date()

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The Going Out could not be saved.")
        }
        let id = goingOut.id?.uuidString ?? "unknown"
        return "\(verb) [goingOut id=\(id)] \(goingOut.title): \(changes.joined(separator: ", "))."
    }

    private static func applyGoingOutText(
        _ arguments: [String: JSONValue], to goingOut: CDGoingOut
    ) -> [String] {
        var changes: [String] = []
        if let title = nonEmpty(arguments["title"]?.stringValue) {
            goingOut.title = title
            changes.append("title")
        }
        if let destination = arguments["destination"]?.stringValue {
            goingOut.destination = destination.trimmed()
            changes.append("destination")
        }
        if let purpose = arguments["purpose"]?.stringValue {
            goingOut.purpose = purpose.trimmed()
            changes.append("purpose")
        }
        if let supervisor = arguments["supervisor_name"]?.stringValue {
            goingOut.supervisorName = supervisor.trimmed()
            changes.append("supervisor")
        }
        if let notes = arguments["notes"]?.stringValue {
            goingOut.notes = notes.trimmed()
            changes.append("notes")
        }
        return changes
    }

    private static func applyGoingOutDates(
        _ arguments: [String: JSONValue], to goingOut: CDGoingOut
    ) throws -> [String] {
        var changes: [String] = []
        if let proposed = try dayArgument(arguments, "proposed_date") {
            goingOut.proposedDate = proposed
            changes.append("proposed \(dayString(proposed))")
        }
        if let actual = try dayArgument(arguments, "actual_date") {
            goingOut.actualDate = actual
            changes.append("happened \(dayString(actual))")
        }
        return changes
    }

    private static func applyGoingOutStatus(
        _ arguments: [String: JSONValue], to goingOut: CDGoingOut
    ) throws -> [String] {
        var changes: [String] = []
        if let status = try goingOutStatusArgument(arguments, "status") {
            goingOut.status = status
            changes.append(status.rawValue)
        }
        if let raw = nonEmpty(arguments["permission_status"]?.stringValue) {
            guard let permission = PermissionStatus(rawValue: raw) else {
                let allowed = PermissionStatus.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("permission_status must be one of: \(allowed). Got \"\(raw)\".")
            }
            goingOut.permissionStatus = permission
            changes.append("permissions \(permission.rawValue)")
        }
        return changes
    }

    private static func applyGoingOutStudents(
        _ arguments: [String: JSONValue], to goingOut: CDGoingOut,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let entries = arguments["student_names"]?.arrayValue else { return [] }
        let names = entries.compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let ids = students.compactMap(\.id)
        guard ids.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        goingOut.studentIDsArray = ids.map(\.uuidString)
        return students.isEmpty
            ? ["cleared the students"]
            : ["\(students.count) student(s) going"]
    }

    private static func goingOutStatusArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> GoingOutStatus? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let status = GoingOutStatus(rawValue: raw) else {
            let allowed = GoingOutStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return status
    }

    private static func resolveGoingOut(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDGoingOut {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("going_out_id must be a uuid, got \"\(reference)\".")
        }
        let request = CDFetchRequest(CDGoingOut.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let goingOut = modelContext.safeFetch(request).first else {
            throw MCPToolError("No Going Out with id \(reference) was found.")
        }
        return goingOut
    }
}
