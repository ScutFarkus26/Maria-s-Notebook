//
//  MCPNotebookTools+ScheduleWrites.swift
//  Maria's Notebook
//
//  Putting a lesson on the calendar and moving it.
//
//  Writes go through PresentationFactory and the assignment's own
//  schedule/unschedule helpers — the same paths the planner and the calendar's
//  drag-to-reschedule use — so a plan made over MCP is completed rather than
//  duplicated when record_presentation files it later.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Scheduling a Presentation

    static func schedulePresentationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "schedule_presentation",
            title: "Schedule Presentation",
            description: "Plan a lesson to be given to one or more students on a day. Creates the "
                + "plan the same way the in-app planner does, so it appears on the calendar and is "
                + "completed rather than duplicated when record_presentation files it later. "
                + "If the same lesson is already planned for exactly these students, that plan is "
                + "moved to the new day instead of a second one being created.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson": [
                        "type": "string",
                        "description": "The lesson to plan: a lesson id from find_lessons, or its exact name"
                    ],
                    "student_names": [
                        "type": "array",
                        "items": ["type": "string"],
                        "minItems": 1,
                        "description": "The students it will be given to"
                    ],
                    "date": [
                        "type": "string",
                        "description": "The day to schedule it for, YYYY-MM-DD"
                    ]
                ],
                "required": ["lesson", "student_names", "date"]
            ],
            handler: { arguments in
                try schedulePresentation(arguments: arguments, in: context())
            }
        )
    }

    private static func schedulePresentation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lesson = try resolveLessonReference(requireString(arguments, "lesson"), in: modelContext)
        guard let lessonID = lesson.id else {
            throw MCPToolError("\"\(lesson.name)\" has no saved identifier and cannot be scheduled.")
        }
        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        guard let day = try dayArgument(arguments, "date") else {
            throw MCPToolError("A date is required, formatted YYYY-MM-DD.")
        }

        let existing = plannedAssignment(
            lessonID: lessonID, studentIDs: Set(studentIDs), in: modelContext
        )
        let assignment = existing
            ?? PresentationFactory.makeDraft(lesson: lesson, students: students, context: modelContext)
        assignment.schedule(onDay: day)

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be scheduled.")
        }

        let id = assignment.id?.uuidString ?? "unknown"
        let who = students.map(\.fullName).joined(separator: ", ")
        let verb = existing == nil ? "Scheduled" : "Moved the existing plan for"
        return "\(verb) [presentation id=\(id)] \(lesson.name) — \(who) on \(dayString(day))."
    }

    /// A plan for this lesson and exactly these students that has not been given
    /// yet. Matching the full student set (not a subset) keeps a group plan from
    /// being silently rewritten when the guide schedules the lesson for one child.
    private static func plannedAssignment(
        lessonID: UUID, studentIDs: Set<UUID>, in modelContext: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        return modelContext.safeFetch(request)
            .filter { !$0.isPresented && Set($0.studentUUIDs) == studentIDs }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .first
    }

    // MARK: - Rescheduling

    static func reschedulePresentationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "reschedule_presentation",
            title: "Reschedule Presentation",
            description: "Move a planned presentation to another day, or take it off the calendar "
                + "entirely (it returns to the planning list rather than being deleted). Presentations "
                + "already given cannot be rescheduled — correct those with record_presentation.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "presentation_id": [
                        "type": "string",
                        "description": "The presentation's id, as returned by schedule_for_range"
                    ],
                    "date": [
                        "type": "string",
                        "description": "The new day, YYYY-MM-DD. Omit when unscheduling."
                    ],
                    "unschedule": [
                        "type": "boolean",
                        "description": "Take the presentation off the calendar, back to the planning list"
                    ]
                ],
                "required": ["presentation_id"]
            ],
            handler: { arguments in
                try reschedulePresentation(arguments: arguments, in: context())
            }
        )
    }

    private static func reschedulePresentation(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "presentation_id")
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("presentation_id must be a uuid, got \"\(reference)\".")
        }
        let repository = PresentationRepository(context: modelContext)
        guard let assignment = repository.fetchLessonAssignment(id: id) else {
            throw MCPToolError("No presentation with id \(reference) was found.")
        }
        guard !assignment.isPresented else {
            throw MCPToolError(
                "That presentation has already been given, so it has no place on the calendar to move."
            )
        }

        let title = nonEmpty(assignment.lessonTitleSnapshot)
            ?? assignment.lesson?.name ?? "The presentation"
        let unschedule = arguments["unschedule"]?.boolValue ?? false
        let day = try dayArgument(arguments, "date")

        let outcome: String
        if unschedule {
            assignment.unschedule()
            outcome = "\(title) is off the calendar and back in the planning list."
        } else if let day {
            assignment.schedule(onDay: day)
            outcome = "\(title) is now scheduled for \(dayString(day))."
        } else {
            throw MCPToolError("Pass a new date, or unschedule: true to take it off the calendar.")
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be rescheduled.")
        }
        return "[presentation id=\(id.uuidString)] \(outcome)"
    }
}
