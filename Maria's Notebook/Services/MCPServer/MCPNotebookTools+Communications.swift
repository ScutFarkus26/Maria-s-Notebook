//
//  MCPNotebookTools+Communications.swift
//  Maria's Notebook
//
//  Letters and reports home.
//
//  `record_parent_communication` files what was written and where it stands —
//  it never sends anything. Delivery to families stays in the app, where the
//  guide reviews it first.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Communications Home

    static func parentCommunicationsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "parent_communications",
            title: "Parent Communications",
            description: "Letters and reports home: what was written, its status (draft, "
                + "reviewed, sent), and when it went. Filter by student, month, or status.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "Only communications about this student"
                    ],
                    "month": [
                        "type": "string",
                        "description": "Only this report month, YYYY-MM"
                    ],
                    "status": [
                        "type": "string",
                        "enum": ["draft", "reviewed", "sent"],
                        "description": "Only communications in this state"
                    ],
                    "include_body": [
                        "type": "boolean",
                        "description": "Include the full text of each one (default false)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeCommunications(arguments: arguments, in: context())
            }
        )
    }

    private static func describeCommunications(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }
        let month = nonEmpty(arguments["month"]?.stringValue)
        let status = try reportStatusArgument(arguments, "status")
        let includeBody = arguments["include_body"]?.boolValue ?? false

        let request = CDFetchRequest(CDParentCommunication.self)
        if let studentID = student?.id {
            request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        }
        let matched = modelContext.safeFetch(request)
            .filter { month == nil || $0.monthKey == month }
            .filter { status == nil || $0.status == status }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        guard !matched.isEmpty else {
            return "No communications match that."
        }

        let names = studentNameIndex(in: modelContext)
        let lines = matched.map { communication -> String in
            let id = communication.id?.uuidString ?? "unknown"
            let child = names[communication.studentID] ?? "unknown student"
            var details = [communication.communicationType.rawValue, communication.status.displayName]
            if let monthKey = nonEmpty(communication.monthKey) {
                details.append(monthKey)
            }
            if let sentAt = communication.sentAt {
                details.append("sent \(dayString(sentAt))")
            }
            if communication.aiGenerated {
                details.append("AI drafted")
            }
            let head = "- [communication id=\(id)] \(child): \(communication.subject) "
                + "(\(details.joined(separator: ", ")))"
            guard includeBody, let body = nonEmpty(communication.body) else { return head }
            return head + "\n    " + body.replacingOccurrences(of: "\n", with: "\n    ")
        }
        return "\(matched.count) communication(s):\n" + lines.joined(separator: "\n")
    }

    static func recordParentCommunicationTool(
        context: @escaping MCPContextProvider
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "record_parent_communication",
            title: "Record Parent Communication",
            description: "File a letter or report home in the student's record — what was "
                + "written and where it stands. This does not send anything: sending stays in "
                + "the app so the guide reviews it first. Pass communication_id to update an "
                + "existing one (for example to mark it sent).",
            inputSchema: recordCommunicationSchema,
            annotations: .write,
            handler: { arguments in
                try recordParentCommunication(arguments: arguments, in: context())
            }
        )
    }

    private static let recordCommunicationSchema: JSONValue = [
        "type": "object",
        "properties": [
            "communication_id": [
                "type": "string",
                "description": "An existing communication to update. Omit to file a new one."
            ],
            "student_name": [
                "type": "string",
                "description": "The child it is about (required when filing a new one)"
            ],
            "subject": ["type": "string", "description": "The subject line"],
            "body": ["type": "string", "description": "The text of the letter or report"],
            "type": [
                "type": "string",
                "enum": [
                    "conference", "progressUpdate", "monthlyReport", "concern",
                    "introduction", "endOfYear", "custom"
                ],
                "description": "What kind of communication it is"
            ],
            "status": [
                "type": "string",
                "enum": ["draft", "reviewed", "sent"],
                "description": .string("Where it stands. Marking it sent stamps the sent date "
                    + "unless sent_date is given.")
            ],
            "sent_date": ["type": "string", "description": "The day it went home, YYYY-MM-DD"],
            "month": ["type": "string", "description": "The report month it belongs to, YYYY-MM"],
            "notes": ["type": "string", "description": "Private notes for the guide"]
        ]
    ]

    private static func recordParentCommunication(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let communication: CDParentCommunication
        let verb: String
        if let reference = nonEmpty(arguments["communication_id"]?.stringValue) {
            communication = try resolveCommunication(reference, in: modelContext)
            verb = "Updated"
        } else {
            communication = try makeCommunication(arguments, in: modelContext)
            verb = "Filed"
        }

        var changes: [String] = []
        if let subject = nonEmpty(arguments["subject"]?.stringValue) {
            communication.subject = subject
            changes.append("subject")
        }
        if let body = arguments["body"]?.stringValue {
            communication.body = body
            changes.append("body")
        }
        if let raw = nonEmpty(arguments["type"]?.stringValue) {
            guard let type = CommunicationType(rawValue: raw) else {
                let allowed = CommunicationType.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("type must be one of: \(allowed). Got \"\(raw)\".")
            }
            communication.communicationType = type
            changes.append(type.rawValue)
        }
        if let monthKey = nonEmpty(arguments["month"]?.stringValue) {
            communication.monthKey = monthKey
            changes.append("month \(monthKey)")
        }
        if let notes = arguments["notes"]?.stringValue {
            communication.notes = notes.trimmed()
            changes.append("notes")
        }
        changes += try applyCommunicationStatus(arguments, to: communication)
        communication.modifiedAt = Date()

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The communication could not be saved.")
        }
        let id = communication.id?.uuidString ?? "unknown"
        return "\(verb) [communication id=\(id)] \(communication.subject): "
            + changes.joined(separator: ", ") + "."
    }

    /// Marking something sent stamps the date, because a "sent" letter with no
    /// date reads as unsent everywhere else in the app.
    private static func applyCommunicationStatus(
        _ arguments: [String: JSONValue], to communication: CDParentCommunication
    ) throws -> [String] {
        let explicitDate = try dayArgument(arguments, "sent_date")
        guard let status = try reportStatusArgument(arguments, "status") else {
            guard let explicitDate else { return [] }
            communication.sentAt = explicitDate
            return ["sent \(dayString(explicitDate))"]
        }
        communication.status = status
        guard status == .sent else {
            communication.sentAt = nil
            return ["marked \(status.displayName.lowercased())"]
        }
        let sentAt = explicitDate ?? Date()
        communication.sentAt = sentAt
        return ["marked sent \(dayString(sentAt))"]
    }

    private static func makeCommunication(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> CDParentCommunication {
        guard let studentReference = nonEmpty(arguments["student_name"]?.stringValue) else {
            throw MCPToolError("Filing a new communication needs student_name.")
        }
        let student = try resolveStudentReference(studentReference, in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let communication = CDParentCommunication(context: modelContext)
        communication.id = UUID()
        communication.studentID = studentID.uuidString
        communication.createdAt = Date()
        communication.status = .draft
        return communication
    }

    private static func resolveCommunication(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDParentCommunication {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("communication_id must be a uuid, got \"\(reference)\".")
        }
        let request = CDFetchRequest(CDParentCommunication.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let communication = modelContext.safeFetch(request).first else {
            throw MCPToolError("No communication with id \(reference) was found.")
        }
        return communication
    }

    private static func reportStatusArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> MonthlyReportStatus? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let status = MonthlyReportStatus(rawValue: raw) else {
            let allowed = MonthlyReportStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return status
    }
}
