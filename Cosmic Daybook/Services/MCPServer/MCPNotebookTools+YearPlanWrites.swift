//
//  MCPNotebookTools+YearPlanWrites.swift
//  Cosmic Daybook
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
            description: "Change one year-plan entry: move its target date (the later planned lessons "
                + "in her sequence move with it, keeping their spacing, as a drag on the year plan "
                + "does), mark it skipped, or put a skipped one back to planned. Skipping never "
                + "deletes — the entry stays readable through year_plan and can be restored. "
                + "Entries already promoted onto the calendar are refused: they belong to a real "
                + "presentation now, so move that with reschedule_presentation instead.",
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
                        "description": .string("The new target day, YYYY-MM-DD. A day the school "
                            + "is closed moves forward to the next open one, and the reply says so.")
                    ]
                ],
                "required": ["entry_id"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { try updateYearPlanEntry(arguments: arguments, in: $0) }
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

        // A target is a day the guide means to give the lesson, so it has to be
        // a day the school is open. Asking for Rosh Hashana gets the next open
        // morning rather than a refusal — but the reply never lets that pass
        // silently, or the plan and the answer would disagree.
        let moved: String = day.map { moveYearPlanEntry(entry, to: $0, in: modelContext) } ?? ""

        guard modelContext.safeSave() else {
            throw MCPToolError("The year-plan entry could not be saved.")
        }
        let lessons: [UUID: String] = lessonNameIndex(in: modelContext)
        let line: String = yearPlanEntryLine(entry, lessons: lessons, includeStatus: true)
        return moved + "Updated " + line
    }

    /// Moves one entry's target to `day` and says what happened beyond the
    /// move itself. A planned entry moves the way a drag on the year plan
    /// moves it (`YearPlanPacing.reschedule`): the lessons after it in her
    /// sequence shift with it, keeping their spacing, so none is left ahead
    /// of it (domain-logic review R17). A skipped one just takes the date.
    private static func moveYearPlanEntry(
        _ entry: CDYearPlanEntry, to day: Date, in modelContext: NSManagedObjectContext
    ) -> String {
        let asked: Date = AppCalendar.startOfDay(day)
        let landing: Date
        var successors: String = ""
        if entry.isPlanned {
            let move = YearPlanPacing.reschedule(entry, to: asked, in: modelContext)
            landing = move.landing
            let count: Int = move.successorsMoved
            if count > 0 {
                let lessons: String = count == 1 ? "1 later lesson" : "\(count) later lessons"
                successors = "\(lessons) in the sequence moved with it, keeping their spacing.\n"
            }
        } else {
            landing = YearPlanPacing.schoolDay(onOrAfter: asked, in: modelContext)
            entry.plannedDate = landing
            entry.modifiedAt = Date()
        }
        guard landing != asked else { return successors }
        let from: String = dayString(asked)
        let to: String = dayString(landing)
        return "\(from) is not a school day, so the target moved to \(to).\n" + successors
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
            annotations: .destructive,
            handler: { arguments in
                try undoingOnFailure(context()) { try skipYearPlanEntries(arguments: arguments, in: $0) }
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
            MCPCallOutcome.markNothingWritten()
            return "\(student.fullName) has no planned year-plan entries to skip."
        }
        let satisfaction = YearPlanSatisfaction.index(for: entries, in: modelContext)
        let yearStart = YearPlanStaleness.currentYearStart()
        let behind = entries.filter {
            $0.isBehindPace(satisfiedBy: satisfaction, schoolYearStart: yearStart)
        }.count
        let carried = entries.filter { $0.isCarriedOver(yearStart: yearStart) }.count
        let skipped = StudentDeparturePlans.skip(entries: entries)

        guard modelContext.safeSave() else {
            throw MCPToolError("The year-plan entries could not be saved.")
        }
        let behindNote = behind > 0 ? " \(behind) of them had gone behind pace." : ""
        let carriedNote = carried > 0
            ? " \(carried) of them \(carried == 1 ? "is" : "are") carried over from last year."
            : ""
        return "Skipped \(skipped) year-plan \(skipped == 1 ? "entry" : "entries") for "
            + "\(student.fullName).\(behindNote)\(carriedNote) Nothing was deleted — read them "
            + "back with year_plan status \"skipped\"."
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
