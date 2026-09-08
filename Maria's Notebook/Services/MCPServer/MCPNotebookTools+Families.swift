//
//  MCPNotebookTools+Families.swift
//  Maria's Notebook
//
//  The guardians on file for each child.
//
//  This is the most sensitive corner of the notebook — real names and real
//  email addresses. The tools read and write it because the guide asked for
//  it; nothing here contacts anybody.
//
//  Letters home live in MCPNotebookTools+Communications.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Guardians

    static func listGuardiansTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_guardians",
            title: "List Guardians",
            description: "The guardians on file: name, relationship, email, and whether they "
                + "receive reports. For one student, or the whole class.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "Only this student's guardians (omit for the whole class)"
                    ],
                    "receives_reports_only": [
                        "type": "boolean",
                        "description": "Only guardians flagged to receive reports (default false)"
                    ]
                ]
            ],
            handler: { arguments in
                let modelContext = context()
                let student = try nonEmpty(arguments["student_name"]?.stringValue)
                    .map { try resolveStudentReference($0, in: modelContext) }
                let reportsOnly = arguments["receives_reports_only"]?.boolValue ?? false
                return describeGuardians(for: student, reportsOnly: reportsOnly, in: modelContext)
            }
        )
    }

    private static func describeGuardians(
        for student: CDStudent?, reportsOnly: Bool, in modelContext: NSManagedObjectContext
    ) -> String {
        let request = CDFetchRequest(CDGuardian.self)
        if let studentID = student?.id {
            request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        }
        let guardians = modelContext.safeFetch(request)
            .filter { !reportsOnly || $0.receivesReports }

        guard !guardians.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return "No guardians are on file\(who)."
        }

        let names = studentNameIndex(in: modelContext)
        let sorted = guardians.sorted { lhs, rhs in
            let leftChild = names[lhs.studentID] ?? ""
            let rightChild = names[rhs.studentID] ?? ""
            if leftChild != rightChild { return leftChild < rightChild }
            return lhs.sortOrder < rhs.sortOrder
        }
        let lines = sorted.map { guardian -> String in
            let id = guardian.id?.uuidString ?? "unknown"
            let child = names[guardian.studentID] ?? "unknown student"
            var details = [guardian.relationship.rawValue]
            if let email = nonEmpty(guardian.email) {
                details.append(email)
            } else {
                details.append("no email on file")
            }
            if guardian.receivesReports {
                details.append("receives reports")
            }
            return "- [guardian id=\(id)] \(guardian.name) — \(child) (\(details.joined(separator: ", ")))"
        }
        return "\(sorted.count) guardian(s):\n" + lines.joined(separator: "\n")
    }

    static func updateGuardianTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_guardian",
            title: "Add Or Update Guardian",
            description: "Add a guardian for a student, or edit one by id: name, email, "
                + "relationship, whether they receive reports, and notes. Pass guardian_id to "
                + "edit; pass student_name and name to add. Only the fields provided are changed.",
            inputSchema: updateGuardianSchema,
            handler: { arguments in
                try updateGuardian(arguments: arguments, in: context())
            }
        )
    }

    private static let updateGuardianSchema: JSONValue = [
        "type": "object",
        "properties": [
            "guardian_id": [
                "type": "string",
                "description": "The guardian to edit, as returned by list_guardians. Omit to add a new one."
            ],
            "student_name": [
                "type": "string",
                "description": "The child this guardian belongs to (required when adding)"
            ],
            "name": ["type": "string", "description": "The guardian's name"],
            "email": ["type": "string", "description": "Email address"],
            "relationship": [
                "type": "string",
                "enum": ["parent", "mother", "father", "guardian", "grandparent", "other"],
                "description": "How they relate to the child"
            ],
            "receives_reports": [
                "type": "boolean",
                "description": "Whether monthly reports go to this guardian"
            ],
            "notes": ["type": "string", "description": "Anything worth remembering"]
        ]
    ]

    private static func updateGuardian(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let guardian: CDGuardian
        let verb: String
        if let reference = nonEmpty(arguments["guardian_id"]?.stringValue) {
            guardian = try resolveGuardian(reference, in: modelContext)
            verb = "Updated"
        } else {
            guardian = try makeGuardian(arguments, in: modelContext)
            verb = "Added"
        }

        var changes: [String] = []
        if let name = nonEmpty(arguments["name"]?.stringValue) {
            guardian.name = name
            changes.append("name")
        }
        if let email = arguments["email"]?.stringValue {
            guardian.email = email.trimmed()
            changes.append("email")
        }
        if let raw = nonEmpty(arguments["relationship"]?.stringValue) {
            guard let relationship = GuardianRelationship(rawValue: raw) else {
                let allowed = GuardianRelationship.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("relationship must be one of: \(allowed). Got \"\(raw)\".")
            }
            guardian.relationship = relationship
            changes.append("relationship")
        }
        if let receives = arguments["receives_reports"]?.boolValue {
            guardian.receivesReports = receives
            changes.append(receives ? "receives reports" : "no longer receives reports")
        }
        if let notes = arguments["notes"]?.stringValue {
            guardian.notes = notes.trimmed()
            changes.append("notes")
        }
        guardian.modifiedAt = Date()

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard guardian.name.trimmed().isEmpty == false else {
            modelContext.rollback()
            throw MCPToolError("A guardian needs a name.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The guardian could not be saved.")
        }
        let id = guardian.id?.uuidString ?? "unknown"
        return "\(verb) [guardian id=\(id)] \(guardian.name): \(changes.joined(separator: ", "))."
    }

    private static func makeGuardian(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> CDGuardian {
        guard let studentReference = nonEmpty(arguments["student_name"]?.stringValue) else {
            throw MCPToolError("Adding a guardian needs student_name (and a name).")
        }
        let student = try resolveStudentReference(studentReference, in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let guardian = CDGuardian(context: modelContext)
        guardian.id = UUID()
        guardian.studentID = studentID.uuidString
        guardian.createdAt = Date()
        return guardian
    }

    private static func resolveGuardian(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDGuardian {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("guardian_id must be a uuid, got \"\(reference)\".")
        }
        let request = CDFetchRequest(CDGuardian.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let guardian = modelContext.safeFetch(request).first else {
            throw MCPToolError("No guardian with id \(reference) was found.")
        }
        return guardian
    }
}
