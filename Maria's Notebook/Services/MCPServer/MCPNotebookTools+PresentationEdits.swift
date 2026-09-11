//
//  MCPNotebookTools+PresentationEdits.swift
//  Maria's Notebook
//
//  Changing a planned presentation without recreating it: reshaping who is
//  in the group, or discarding the plan outright.
//
//  `reschedule_presentation(unschedule: true)` takes a lesson off the
//  calendar but leaves it in the planning list; until now nothing over MCP
//  could discard a plan the guide has decided against, so a regrouped
//  presentation left its original sitting in the list. `discard_presentation`
//  is the second tool that deletes a row, and it follows
//  `remove_student_from_work`'s shape: a call without `confirm` reports the
//  lesson, the day, the roster and the notes that hang off it, and writes
//  nothing; a call with `confirm: true` deletes at once, whether or not a
//  report was asked for first — the report is offered, never required, so a
//  caller who already knows the presentation id can discard it in one call.
//  The delete itself is the one the planning list's context menu
//  makes — `context.delete` + save, notes cascading — plus one repair that
//  menu does not make: a year-plan entry promoted into the discarded plan
//  goes back to `planned`, so the intention survives the plan.
//
//  Given presentations are history and are refused by both tools;
//  `record_presentation` corrects those.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Discard

    static func discardPresentationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "discard_presentation",
            title: "Discard Presentation",
            description: "Drop a planned presentation altogether — off the calendar and out of the "
                + "planning list — for a plan the guide has decided against. Called without "
                + "confirm it only reports what would go — the lesson, the day, who was in the "
                + "group, and any notes written on it — and deletes nothing. Called with "
                + "confirm: true it deletes immediately, in that one call, with the same report as "
                + "its receipt; a preview call first is optional, not required. Presentations "
                + "already given are refused; correct those with record_presentation. To take a "
                + "plan off the calendar but keep it, use reschedule_presentation with unschedule "
                + "instead.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "presentation_id": [
                        "type": "string",
                        "description": .string("The presentation's id, as returned by schedule_for_range "
                            + "or student_presentation_history")
                    ],
                    "confirm": [
                        "type": "boolean",
                        "description": .string("true deletes the presentation in this call. Omit (or false) "
                            + "to get the report only, with nothing changed.")
                    ]
                ],
                "required": ["presentation_id"]
            ],
            annotations: .destructive,
            handler: { arguments in
                try discardPresentation(arguments: arguments, in: context())
            }
        )
    }

    private static func discardPresentation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let assignment = try resolvePlannedPresentation(requireString(arguments, "presentation_id"), in: modelContext)
        let id: String = assignment.id?.uuidString ?? "unknown"
        let notes: Int = assignment.unifiedNotes?.count ?? 0
        let promoted = promotedYearPlanEntries(for: assignment, in: modelContext)

        var report: [String] = ["[presentation id=\(id)] \(presentationSummary(assignment, in: modelContext))"]
        report.append(notes == 0 ? "No notes are written on it." : "\(notes) note(s) written on it would go with it.")
        if !promoted.isEmpty {
            report.append("\(promoted.count) year-plan entr\(promoted.count == 1 ? "y" : "ies") promoted into it "
                + "would return to planned.")
        }

        guard arguments["confirm"]?.boolValue == true else {
            return "discard_presentation refused — nothing has been changed.\n"
                + "Re-call with confirm: true to delete it.\n\n" + report.joined(separator: "\n")
        }

        for entry in promoted {
            entry.status = .planned
            entry.promotedAssignmentID = nil
        }
        modelContext.delete(assignment)
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be discarded.")
        }
        return "Discarded.\n\n" + report.joined(separator: "\n")
    }

    /// Year-plan entries that became this presentation. The in-app delete
    /// leaves them pointing at nothing, still reading as promoted; returning
    /// them to planned keeps the plan honest.
    private static func promotedYearPlanEntries(
        for assignment: CDLessonAssignment, in modelContext: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        guard let id = assignment.id?.uuidString else { return [] }
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "promotedAssignmentID == %@", id)
        return modelContext.safeFetch(request).filter(\.isPromoted)
    }

    // MARK: - Roster

    static func updatePresentationRosterTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_presentation_roster",
            title: "Update Presentation Roster",
            description: "Change who is in the group for a planned presentation, in place — add "
                + "children, take children off, or both — so regrouping never leaves a stale copy "
                + "in the planning list. Refuses to empty the group (discard_presentation is for "
                + "that), refuses presentations already given, and refuses to add a withdrawn or "
                + "transferred child — though taking one off is how a departure is cleaned up.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "presentation_id": [
                        "type": "string",
                        "description": .string("The presentation's id, as returned by schedule_for_range "
                            + "or student_presentation_history")
                    ],
                    "add_students": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Children to add: first names, full names, or nicknames"
                    ],
                    "remove_students": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Children to take off the group"
                    ]
                ],
                "required": ["presentation_id"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try updatePresentationRoster(arguments: arguments, in: context())
            }
        )
    }

    private static func updatePresentationRoster(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let assignment = try resolvePlannedPresentation(requireString(arguments, "presentation_id"), in: modelContext)
        let adding = try stringArrayArgument(arguments, "add_students")
            .map { try resolveStudentReference($0, in: modelContext) }
        let removing = try stringArrayArgument(arguments, "remove_students")
            .map { try resolveStudentReference($0, in: modelContext) }
        guard !adding.isEmpty || !removing.isEmpty else {
            throw MCPToolError("Pass add_students, remove_students, or both.")
        }
        // Only the children being added: taking a departed child off a group
        // is exactly how a withdrawal is cleaned up.
        try requireEnrolledToJoinRoster(adding)

        var roster: [String] = assignment.studentIDs
        var changes: [String] = []
        for student in removing {
            guard let id = student.id?.uuidString, roster.contains(id) else {
                throw MCPToolError("\(student.fullName) is not in this presentation's group.")
            }
            roster.removeAll { $0 == id }
            changes.append("removed \(student.fullName)")
        }
        for student in adding {
            guard let id = student.id?.uuidString else { continue }
            guard !roster.contains(id) else {
                changes.append("\(student.fullName) was already in the group")
                continue
            }
            roster.append(id)
            changes.append("added \(student.fullName)")
        }
        guard !roster.isEmpty else {
            throw MCPToolError(
                "That would leave nobody in the group. Use discard_presentation to drop the plan instead."
            )
        }
        guard roster != assignment.studentIDs else {
            return "[presentation id=\(assignment.id?.uuidString ?? "unknown")] Nothing changed: "
                + changes.joined(separator: ", ") + "."
        }

        // The same write the detail view's Save and the departure retraction make.
        assignment.studentIDs = roster
        assignment.confirmedStudentIDs = assignment.confirmedStudentIDs.filter { roster.contains($0) }
        assignment.modifiedAt = Date()
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be saved.")
        }
        let id: String = assignment.id?.uuidString ?? "unknown"
        return "[presentation id=\(id)] \(changes.joined(separator: ", ")). "
            + "Now: \(presentationSummary(assignment, in: modelContext))"
    }

    // MARK: - Shared

    /// A presentation that has not been given, by id. Given presentations are
    /// history; both tools here refuse them.
    private static func resolvePlannedPresentation(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("presentation_id must be a uuid, got \"\(reference)\".")
        }
        guard let assignment = PresentationRepository(context: modelContext).fetchLessonAssignment(id: id) else {
            throw MCPToolError("No presentation with id \(reference) was found.")
        }
        guard !assignment.isPresented else {
            throw MCPToolError(
                "That presentation has already been given, so it is history rather than a plan. "
                    + "Correct it with record_presentation."
            )
        }
        return assignment
    }

    /// "Racks and Tubes — scheduled 2026-09-12 — Ora Levi, Etty Klein".
    private static func presentationSummary(
        _ assignment: CDLessonAssignment, in modelContext: NSManagedObjectContext
    ) -> String {
        let title = nonEmpty(assignment.lessonTitleSnapshot) ?? assignment.lesson?.name ?? "Lesson"
        let when = assignment.scheduledFor.map { "scheduled \(dayString($0))" } ?? "not yet scheduled"
        let names = studentNameIndex(in: modelContext)
        let roster = assignment.studentIDs.map { names[$0] ?? "an unknown student" }
        let who = roster.isEmpty ? "nobody" : roster.joined(separator: ", ")
        return "\(title) — \(when) — \(who)"
    }
}
