//
//  MCPNotebookTools+Issues.swift
//  Cosmic Daybook
//
//  Things that need sorting out — a broken shelf, a recurring conflict, a
//  safety worry — and the community topics the class discusses together.
//
//  Resolving an issue stamps `resolvedAt` alongside the status, because an
//  issue marked resolved with no date reads as unresolved in the issue list.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Issues

    static func listIssuesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_issues",
            title: "List Issues",
            description: "Classroom issues being tracked: what is open, how urgent, who it "
                + "concerns, and how the resolved ones were settled.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "status": [
                        "type": "string",
                        "enum": ["Open", "Investigating", "In Progress", "Resolved", "Closed"],
                        "description": "Only issues in this state (default: everything unresolved)"
                    ],
                    "category": [
                        "type": "string",
                        "enum": [
                            "Behavioral", "Social", "Facility", "Supply",
                            "Safety", "Health", "Communication", "Other"
                        ],
                        "description": "Only issues in this category"
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "Only issues concerning this student"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeIssues(arguments: arguments, in: context())
            }
        )
    }

    private static func describeIssues(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let status: IssueStatus? = try issueStatusArgument(arguments, "status")
        let category: IssueCategory? = try issueCategoryArgument(arguments, "category")
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }

        let all: [CDIssue] = modelContext.safeFetch(CDFetchRequest(CDIssue.self))
        let studentID: UUID? = student?.id
        var kept: [CDIssue] = []
        for issue in all where keeps(issue, status: status, category: category, studentID: studentID) {
            kept.append(issue)
        }
        guard !kept.isEmpty else {
            return status == nil ? "No issues are open." : "No issues match that."
        }

        let names = studentNameIndex(in: modelContext)
        let sorted: [CDIssue] = kept.sorted { lhs, rhs in
            let leftRank: Int = issueRank(lhs.priority)
            let rightRank: Int = issueRank(rhs.priority)
            if leftRank != rightRank { return leftRank < rightRank }
            return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        let lines = sorted.map { issue -> String in
            let id: String = issue.id?.uuidString ?? "unknown"
            var details: [String] = [issue.status.rawValue, issue.priority.rawValue, issue.category.rawValue]
            let who: [String] = issue.studentIDs.compactMap { names[$0] }.sorted()
            if !who.isEmpty {
                details.append(who.joined(separator: ", "))
            }
            if let location = nonEmpty(issue.location) {
                details.append("at \(location)")
            }
            if let resolvedAt = issue.resolvedAt {
                details.append("resolved \(dayString(resolvedAt))")
            }
            let resolution: String = nonEmpty(issue.resolutionSummary)
                .map { "\n    Resolution: \($0)" } ?? ""
            return "- [issue id=\(id)] \(issue.title) (\(details.joined(separator: "; ")))\(resolution)"
        }
        return "\(sorted.count) issue(s):\n" + lines.joined(separator: "\n")
    }

    /// With no status asked for, the useful answer is what still needs
    /// attention — settled issues are noise unless requested by name.
    private static func keeps(
        _ issue: CDIssue, status: IssueStatus?, category: IssueCategory?, studentID: UUID?
    ) -> Bool {
        if let status {
            if issue.status != status { return false }
        } else if issue.status == .resolved || issue.status == .closed {
            return false
        }
        if let category, issue.category != category { return false }
        if let studentID, !issue.studentIDs.contains(studentID.uuidString) { return false }
        return true
    }

    /// Urgent first, so the list reads the way the issue board sorts.
    private static func issueRank(_ priority: IssuePriority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    static func updateIssueTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_issue",
            title: "Raise Or Update Issue",
            description: "Raise a classroom issue, or move one along: its status, priority, "
                + "category, who it concerns, and how it was resolved. Marking it resolved or "
                + "closed stamps the resolution date. Pass issue_id to update; pass title to raise "
                + "a new one.",
            inputSchema: updateIssueSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateIssue(arguments: arguments, in: context())
            }
        )
    }

    private static let updateIssueSchema: JSONValue = [
        "type": "object",
        "properties": [
            "issue_id": [
                "type": "string",
                "description": "The issue to update. Omit to raise a new one."
            ],
            "title": ["type": "string", "description": "What the issue is"],
            "description": ["type": "string", "description": "The detail behind it"],
            "status": [
                "type": "string",
                "enum": ["Open", "Investigating", "In Progress", "Resolved", "Closed"],
                "description": "Where it stands"
            ],
            "priority": [
                "type": "string",
                "enum": ["Low", "Medium", "High", "Urgent"],
                "description": "How pressing it is"
            ],
            "category": [
                "type": "string",
                "enum": [
                    "Behavioral", "Social", "Facility", "Supply",
                    "Safety", "Health", "Communication", "Other"
                ],
                "description": "What kind of issue it is"
            ],
            "location": ["type": "string", "description": "Where in the room, if relevant"],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Replace the students this concerns"
            ],
            "resolution": [
                "type": "string",
                "description": "How it was settled"
            ]
        ]
    ]

    private static func updateIssue(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let issue: CDIssue
        let verb: String
        if let reference = nonEmpty(arguments["issue_id"]?.stringValue) {
            issue = try resolveIssue(reference, in: modelContext)
            verb = "Updated"
        } else {
            guard nonEmpty(arguments["title"]?.stringValue) != nil else {
                throw MCPToolError("Raising an issue needs a title.")
            }
            issue = CDIssue(context: modelContext)
            issue.id = UUID()
            issue.createdAt = Date()
            issue.status = .open
            issue.priority = .medium
            verb = "Raised"
        }

        var changes: [String] = []
        changes += applyIssueText(arguments, to: issue)
        changes += try applyIssueClassification(arguments, to: issue)
        changes += try applyIssueStudents(arguments, to: issue, in: modelContext)
        issue.updatedAt = Date()
        issue.modifiedAt = Date()

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The issue could not be saved.")
        }
        let id: String = issue.id?.uuidString ?? "unknown"
        return "\(verb) [issue id=\(id)] \(issue.title): \(changes.joined(separator: ", "))."
    }

    private static func applyIssueText(
        _ arguments: [String: JSONValue], to issue: CDIssue
    ) -> [String] {
        var changes: [String] = []
        if let title = nonEmpty(arguments["title"]?.stringValue) {
            issue.title = title
            changes.append("title")
        }
        if let detail = arguments["description"]?.stringValue {
            issue.issueDescription = detail.trimmed()
            changes.append("description")
        }
        if let location = arguments["location"]?.stringValue {
            issue.location = location.trimmed()
            changes.append("location")
        }
        if let resolution = nonEmpty(arguments["resolution"]?.stringValue) {
            issue.resolutionSummary = resolution
            changes.append("resolution")
        }
        return changes
    }

    /// Status, priority and category — and the resolution stamp that has to
    /// move with the status.
    private static func applyIssueClassification(
        _ arguments: [String: JSONValue], to issue: CDIssue
    ) throws -> [String] {
        var changes: [String] = []
        if let status = try issueStatusArgument(arguments, "status") {
            issue.status = status
            let settled: Bool = status == .resolved || status == .closed
            issue.resolvedAt = settled ? (issue.resolvedAt ?? Date()) : nil
            changes.append(status.rawValue.lowercased())
        }
        if let priority = try issuePriorityArgument(arguments, "priority") {
            issue.priority = priority
            changes.append("\(priority.rawValue.lowercased()) priority")
        }
        if let category = try issueCategoryArgument(arguments, "category") {
            issue.category = category
            changes.append(category.rawValue.lowercased())
        }
        return changes
    }

    private static func applyIssueStudents(
        _ arguments: [String: JSONValue], to issue: CDIssue,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let entries = arguments["student_names"]?.arrayValue else { return [] }
        let names = entries.compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let ids = students.compactMap(\.id)
        guard ids.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        issue.studentIDs = ids.map(\.uuidString)
        return students.isEmpty
            ? ["cleared the students"]
            : ["concerns \(students.map(\.fullName).joined(separator: ", "))"]
    }

    private static func issueStatusArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> IssueStatus? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let status = IssueStatus(rawValue: raw) else {
            let allowed = IssueStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return status
    }

    private static func issuePriorityArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> IssuePriority? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let priority = IssuePriority(rawValue: raw) else {
            let allowed = IssuePriority.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return priority
    }

    private static func issueCategoryArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> IssueCategory? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let category = IssueCategory(rawValue: raw) else {
            let allowed = IssueCategory.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return category
    }

    private static func resolveIssue(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDIssue {
        try resolveEntity(
            CDIssue.self, reference: reference,
            argument: "issue_id", noun: "issue", in: modelContext
        )
    }
}
