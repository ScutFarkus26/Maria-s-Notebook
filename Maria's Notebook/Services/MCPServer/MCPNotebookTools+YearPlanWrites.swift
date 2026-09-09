//
//  MCPNotebookTools+YearPlanWrites.swift
//  Maria's Notebook
//
//  Changing the year plan: one entry at a time, or a whole child's plan at once.
//
//  A year-plan entry is an intention with a target date. Two boundaries shape
//  these tools. Nothing here deletes — `skipped` is how an intention is
//  retired, so a girl who re-enrols finds her plan where she left it, and
//  `year_plan(status: "skipped")` still reads it back. And nothing here touches
//  a promoted entry: promotion means the entry has become a real assignment on
//  the calendar, that assignment is the truth, and moving the entry behind its
//  back would leave the two disagreeing. `reschedule_presentation` moves those.
//
//  `skip_year_plan_entries` exists because the one-at-a-time path is useless at
//  the scale this actually comes up — a child who left mid-year can be carrying
//  dozens of planned entries, every one of them quietly going behind pace.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Update One Entry

    static func updateYearPlanEntryTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_year_plan_entry",
            title: "Update Year Plan Entry",
            description: "Change one year-plan entry: move its target date, mark it skipped, or "
                + "put a skipped one back to planned. Skipping never deletes — the entry stays "
                + "readable through year_plan and can be restored. Entries already promoted onto "
                + "the calendar are refused: they belong to a real presentation now, so move that "
                + "with reschedule_presentation instead.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "entry_id": [
                        "type": "string",
                        "description": "The entry's id, as returned by year_plan"
                    ],
                    "status": [
                        "type": "string",
                        "enum": ["planned", "promoted", "skipped"],
                        "description": .string(
                            "The new status. Promoting is not done here — a lesson reaches "
                                + "the calendar through schedule_presentation."
                        )
                    ],
                    "target_date": [
                        "type": "string",
                        "description": "The new target day, YYYY-MM-DD"
                    ]
                ],
                "required": ["entry_id"]
            ],
            handler: { arguments in
                try updateYearPlanEntry(arguments: arguments, in: context())
            }
        )
    }

    private static func updateYearPlanEntry(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "entry_id")
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("entry_id must be a uuid, got \"\(reference)\".")
        }
        guard let entry = modelContext.object(CDYearPlanEntry.self, id: id) else {
            throw MCPToolError("No year-plan entry with id \(reference) was found.")
        }
        guard !entry.isPromoted else {
            throw MCPToolError(
                "That entry has already been promoted onto the calendar, so the presentation is "
                    + "what carries its date now. Move it with reschedule_presentation."
            )
        }

        let status = try yearPlanStatusArgument(arguments)
        let day = try dayArgument(arguments, "target_date")
        guard status != nil || day != nil else {
            throw MCPToolError("Pass a status, a target_date, or both.")
        }
        if status == .promoted {
            throw MCPToolError(
                "An entry becomes promoted by the lesson reaching the calendar, which is "
                    + "schedule_presentation's job — it is not a status to set by hand."
            )
        }

        if let status { entry.status = status }
        if let day {
            entry.plannedDate = AppCalendar.startOfDay(day)
            entry.modifiedAt = Date()
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The year-plan entry could not be saved.")
        }
        let lessons = lessonNameIndex(in: modelContext)
        return "Updated " + yearPlanEntryLine(entry, lessons: lessons, includeStatus: true)
    }

    // MARK: - Skip a Whole Plan

    static func skipYearPlanEntriesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "skip_year_plan_entries",
            title: "Skip Year Plan Entries",
            description: "Mark every still-planned year-plan entry for one student skipped, in "
                + "one call — for a child who has withdrawn or transferred, whose plan would "
                + "otherwise go on falling behind pace. Entries already promoted onto the "
                + "calendar are left alone, and nothing is deleted: year_plan with "
                + "status \"skipped\" reads them back, and update_year_plan_entry restores any "
                + "of them to planned.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                try skipYearPlanEntries(arguments: arguments, in: context())
            }
        )
    }

    private static func skipYearPlanEntries(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(
            requireString(arguments, "student_name"), in: modelContext
        )
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }

        // The same call the app makes when a child is withdrawn in the roster,
        // so the two paths cannot drift apart.
        let entries = StudentDeparturePlans.plannedEntries(for: studentID, in: modelContext)
        guard !entries.isEmpty else {
            return "\(student.fullName) has no planned year-plan entries to skip."
        }
        let behind = entries.filter(\.isBehindPace).count
        let skipped = StudentDeparturePlans.skip(entries: entries)

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The year-plan entries could not be saved.")
        }
        let behindNote = behind > 0 ? " \(behind) of them had gone behind pace." : ""
        return "Skipped \(skipped) year-plan \(skipped == 1 ? "entry" : "entries") for "
            + "\(student.fullName).\(behindNote) Nothing was deleted — read them back with "
            + "year_plan status \"skipped\"."
    }

    // MARK: - Shared

    /// Parses the optional `status` argument against the entry statuses,
    /// rejecting anything outside them the way `year_plan`'s filter does.
    private static func yearPlanStatusArgument(
        _ arguments: [String: JSONValue]
    ) throws -> YearPlanEntryStatus? {
        guard let raw = nonEmpty(arguments["status"]?.stringValue) else { return nil }
        guard let status = YearPlanEntryStatus(rawValue: raw) else {
            throw MCPToolError(
                "status must be one of: planned, promoted, skipped. Got \"\(raw)\"."
            )
        }
        return status
    }
}
