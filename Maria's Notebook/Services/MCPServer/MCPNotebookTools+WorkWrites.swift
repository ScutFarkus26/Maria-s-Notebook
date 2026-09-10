//
//  MCPNotebookTools+WorkWrites.swift
//  Maria's Notebook
//
//  Assigning work and moving it along.
//
//  Writes go through WorkRepository and WorkCompletionService — the same paths
//  the Quick New Work sheet and the work detail screen use — so work assigned
//  or completed over MCP carries the same participant rows, track links, and
//  completion history as work created in the app.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Assigning Work

    static func assignWorkTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "assign_work",
            title: "Assign Work",
            description: "Give one or more students work following a lesson. Creates the "
                + "work the same way the in-app Quick New Work sheet does — participant rows, "
                + "track links, and a link back to the presentation the work follows. Assigning "
                + "to several students creates one work item each, linked to one another.",
            inputSchema: assignWorkSchema,
            handler: { arguments in
                try assignWork(arguments: arguments, in: context())
            }
        )
    }

    private static let assignWorkSchema: JSONValue = [
        "type": "object",
        "properties": [
            "lesson": [
                "type": "string",
                "description": "The lesson the work follows: a lesson id from find_lessons, or its exact name"
            ],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "minItems": 1,
                "description": "The students to assign it to"
            ],
            "title": [
                "type": "string",
                "description": "What the work is, in the guide's words (defaults to the lesson name)"
            ],
            "kind": [
                "type": "string",
                "enum": ["practiceLesson", "followUpAssignment", "research", "report"],
                "description": "practiceLesson, followUpAssignment, research, or report"
            ],
            "due_date": [
                "type": "string",
                "description": "When it is due, YYYY-MM-DD (optional)"
            ],
            "check_in_date": [
                "type": "string",
                "description": "Schedule a check-in on this day, YYYY-MM-DD (optional)"
            ],
            "check_in_purpose": [
                "type": "string",
                "description": "What the check-in is for (optional)"
            ]
        ],
        "required": ["lesson", "student_names"]
    ]

    /// Everything `assign_work` needs, resolved and validated before any
    /// managed object is created — so a bad argument fails before a partial
    /// write lands in the context.
    private struct WorkAssignment {
        let lesson: CDLesson
        let lessonID: UUID
        let students: [CDStudent]
        let studentIDs: [UUID]
        let title: String
        let kind: WorkKind?
        let dueDate: Date?
        let checkInDate: Date?
        let checkInPurpose: String
    }

    private static func makeAssignment(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> WorkAssignment {
        let lesson = try resolveLessonReference(requireString(arguments, "lesson"), in: modelContext)
        guard let lessonID = lesson.id else {
            throw MCPToolError("\"\(lesson.name)\" has no saved identifier, so work cannot hang off it.")
        }
        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let former = students.filter { !$0.isEnrolled }
        if !former.isEmpty {
            // Names resolve against every student on file, so a former student
            // still matches; she is refused here with her status rather than
            // quietly put back on the roster through a work item.
            let described = former.map { "\($0.fullName) (\($0.enrollmentStatusRaw))" }.joined(separator: ", ")
            throw MCPToolError(
                "Work can only be assigned to enrolled students. Not enrolled: \(described). "
                    + "list_students shows the current roster."
            )
        }
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        return WorkAssignment(
            lesson: lesson,
            lessonID: lessonID,
            students: students,
            studentIDs: studentIDs,
            title: nonEmpty(arguments["title"]?.stringValue) ?? lesson.name,
            kind: try workKindArgument(arguments, "kind"),
            dueDate: try dayArgument(arguments, "due_date"),
            checkInDate: try dayArgument(arguments, "check_in_date"),
            checkInPurpose: nonEmpty(arguments["check_in_purpose"]?.stringValue) ?? ""
        )
    }

    private static func assignWork(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let assignment = try makeAssignment(arguments: arguments, in: modelContext)
        let created = try createWork(for: assignment, in: modelContext)
        linkParticipants(across: created, in: modelContext)

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The work could not be saved.")
        }

        let ids = created.compactMap { $0.id?.uuidString }
            .map { "[work id=\($0)]" }
            .joined(separator: " ")
        let who = assignment.students.map(\.fullName).joined(separator: ", ")
        let due = assignment.dueDate.map { ", due \(dayString($0))" } ?? ""
        let check = assignment.checkInDate.map { ", check-in \(dayString($0))" } ?? ""
        return "Assigned \"\(assignment.title)\" to \(who)\(due)\(check). \(ids)"
    }

    private static func createWork(
        for assignment: WorkAssignment, in modelContext: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let repository = WorkRepository(context: modelContext)
        var created: [CDWorkModel] = []
        do {
            for studentID in assignment.studentIDs {
                let work = try repository.createWork(
                    studentID: studentID,
                    lessonID: assignment.lessonID,
                    title: assignment.title,
                    kind: assignment.kind,
                    scheduledDate: assignment.dueDate,
                    saveImmediately: false
                )
                if let checkInDate = assignment.checkInDate {
                    CDWorkCheckIn.make(
                        for: work, on: AppCalendar.startOfDay(checkInDate),
                        purpose: assignment.checkInPurpose, in: modelContext
                    )
                }
                created.append(work)
            }
        } catch {
            modelContext.rollback()
            throw MCPToolError("The work could not be created: \(error.localizedDescription)")
        }
        return created
    }

    /// Multi-student work links each item to the others, the way the Quick New
    /// Work sheet does, so the group reads as one piece of work in every view.
    private static func linkParticipants(
        across created: [CDWorkModel], in modelContext: NSManagedObjectContext
    ) {
        guard created.count > 1 else { return }
        for work in created {
            for other in created where other !== work {
                let participant = CDWorkParticipantEntity(context: modelContext)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = work
            }
        }
    }

    private static func workKindArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> WorkKind? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let kind = WorkKind(rawValue: raw) else {
            let allowed = WorkKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return kind
    }

    // MARK: - Updating Work

    static func updateWorkTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_work",
            title: "Update Work",
            description: "Change a work item: move it between active, review and complete, "
                + "set or clear its due date, record which student finished it, or complete a "
                + "scheduled check-in. Completing a work item writes the same completion history "
                + "the in-app work detail does. Only the fields provided are changed.",
            inputSchema: updateWorkSchema,
            handler: { arguments in
                try updateWork(arguments: arguments, in: context())
            }
        )
    }

    private static let updateWorkSchema: JSONValue = [
        "type": "object",
        "properties": [
            "work_id": [
                "type": "string",
                "description": "The work item's id"
            ],
            "status": [
                "type": "string",
                "enum": ["active", "review", "complete"],
                "description": "Move the whole work item to this status"
            ],
            "outcome": [
                "type": "string",
                "enum": ["mastered", "needsMorePractice", "needsReview", "incomplete", "notApplicable"],
                "description": "How it turned out, recorded when completing it"
            ],
            "due_date": [
                "type": "string",
                "description": "New due date, YYYY-MM-DD"
            ],
            "clear_due_date": [
                "type": "boolean",
                "description": "Remove the due date entirely"
            ],
            "completed_by": [
                "type": "string",
                "description": .string("A student who has finished their part — records a "
                    + "completion for that child without closing the whole item")
            ],
            "complete_check_in_on": [
                "type": "string",
                "description": "Mark the check-in scheduled for this day as completed, YYYY-MM-DD"
            ],
            "note": [
                "type": "string",
                "description": "A note to file against the completion"
            ]
        ],
        "required": ["work_id"]
    ]

    private static func updateWork(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let work = try resolveWork(requireString(arguments, "work_id"), in: modelContext)
        guard let workID = work.id else {
            throw MCPToolError("That work item has no identifier.")
        }

        var changes: [String] = []
        changes += try applyStudentCompletion(arguments, to: work, workID: workID, in: modelContext)
        changes += try applyCheckInCompletion(arguments, to: work, in: modelContext)
        changes += try applyDueDate(arguments, to: work)
        changes += try applyStatus(arguments, to: work, workID: workID, in: modelContext)

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field to update.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The work could not be updated.")
        }
        return "[work id=\(workID.uuidString)] \(title(of: work)): "
            + changes.joined(separator: ", ") + "."
    }

    /// Records one child as finished without closing the item for everyone —
    /// group work is often finished at different times.
    private static func applyStudentCompletion(
        _ arguments: [String: JSONValue], to work: CDWorkModel, workID: UUID,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let reference = nonEmpty(arguments["completed_by"]?.stringValue) else { return [] }
        let student = try resolveStudentReference(reference, in: modelContext)
        guard let studentID = student.id, involves(studentID, in: work) else {
            throw MCPToolError("\(student.fullName) is not on this work item.")
        }
        do {
            try WorkCompletionService.markCompleted(
                workID: workID, studentID: studentID,
                note: nonEmpty(arguments["note"]?.stringValue) ?? "",
                in: modelContext
            )
        } catch {
            modelContext.rollback()
            throw MCPToolError("That completion could not be recorded: \(error.localizedDescription)")
        }
        work.participant(for: studentID)?.completedAt = Date()
        return ["recorded \(student.fullName) as finished"]
    }

    private static func applyCheckInCompletion(
        _ arguments: [String: JSONValue], to work: CDWorkModel,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let day = try dayArgument(arguments, "complete_check_in_on") else { return [] }
        let target = AppCalendar.startOfDay(day)
        let match = checkIns(of: work, in: modelContext).first { checkIn in
            guard let date = checkIn.date else { return false }
            return AppCalendar.startOfDay(date) == target && checkIn.status == .scheduled
        }
        guard let checkIn = match else {
            throw MCPToolError("No check-in is scheduled on \(dayString(day)) for this work.")
        }
        checkIn.status = .completed
        return ["completed the check-in on \(dayString(day))"]
    }

    private static func applyDueDate(
        _ arguments: [String: JSONValue], to work: CDWorkModel
    ) throws -> [String] {
        if arguments["clear_due_date"]?.boolValue == true {
            work.dueAt = nil
            return ["cleared the due date"]
        }
        guard let due = try dayArgument(arguments, "due_date") else { return [] }
        work.dueAt = due
        return ["due \(dayString(due))"]
    }

    private static func applyStatus(
        _ arguments: [String: JSONValue], to work: CDWorkModel, workID: UUID,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        let outcome = try completionOutcomeArgument(arguments, "outcome")
        guard let statusRaw = nonEmpty(arguments["status"]?.stringValue) else {
            guard let outcome else { return [] }
            work.completionOutcome = outcome
            return ["outcome \(outcome.displayName)"]
        }
        guard let status = WorkStatus(rawValue: statusRaw) else {
            let allowed = WorkStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("status must be one of: \(allowed). Got \"\(statusRaw)\".")
        }
        guard status == .complete else {
            work.status = status
            return ["moved to \(status.displayName.lowercased())"]
        }
        // Completing runs through the repository so the completion date, outcome
        // and any note land exactly as the in-app control writes them.
        WorkRepository(context: modelContext).markWorkCompleted(
            id: workID, outcome: outcome,
            note: nonEmpty(arguments["note"]?.stringValue)
        )
        return ["marked complete" + (outcome.map { " (\($0.displayName))" } ?? "")]
    }

    private static func completionOutcomeArgument(
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
