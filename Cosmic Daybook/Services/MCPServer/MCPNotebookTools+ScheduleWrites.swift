//
//  MCPNotebookTools+ScheduleWrites.swift
//  Cosmic Daybook
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
            description: "Plan a lesson to be given to one or more students on a day; it appears on the "
                + "calendar and record_presentation completes it later rather than duplicating it. If "
                + "the same lesson is already planned for exactly these students, that plan is moved to "
                + "the new day instead of a second being created. Without a time it lands at 9:00, the "
                + "start of the teaching morning; pass time to place it later. Refuses a day school is "
                + "out, and refuses when any named child already has the lesson on record unless "
                + "purpose says why she is having it again.",
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
                        "description": "The students it will be given to: first names, full names, nicknames, or ids"
                    ],
                    "date": [
                        "type": "string",
                        "description": "The day to schedule it for, YYYY-MM-DD"
                    ],
                    "time": [
                        "type": "string",
                        "description": .string("Optional time of day, HH:MM (24-hour, in the school's local "
                            + "time zone), e.g. \"10:30\". Omit and the lesson takes its place in the "
                            + "morning half of that day, which is how presentations are normally planned "
                            + "— an order within a half, not a timetable.")
                    ],
                    "purpose": repeatPurposeProperty
                ],
                "required": ["lesson", "student_names", "date"]
            ],
            annotations: .write,
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
        try requireEnrolledToSchedule(students)
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        guard let day = try dayArgument(arguments, "date") else {
            throw MCPToolError("A date is required, formatted YYYY-MM-DD.")
        }
        let time = try timeArgument(arguments, "time")
        try requireSchoolDay(day, in: modelContext)

        let purpose = try RepeatPurpose.argument(arguments)
        let index = PresentationRecordIndex(lessonIDs: [lessonID.uuidString], in: modelContext)
        let conflicts = try explainedConflicts(
            lesson: lesson, students: students, on: day, purpose: purpose, index: index
        )

        let existing = plannedAssignment(
            lessonID: lessonID, studentIDs: Set(studentIDs), in: modelContext
        )
        let assignment = existing
            ?? PresentationFactory.makeDraft(lesson: lesson, students: students, context: modelContext)
        schedule(assignment, onDay: day, at: time)
        if let purpose {
            recordRepeatIntent(
                RepeatIntent(
                    purpose: purpose, conflicts: conflicts,
                    lessonID: lessonID.uuidString, index: index
                ),
                draft: assignment, plannedOn: day, in: modelContext
            )
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be scheduled.")
        }

        let id = assignment.id?.uuidString ?? "unknown"
        let who = students.map(\.fullName).joined(separator: ", ")
        let verb = existing == nil ? "Scheduled" : "Moved the existing plan for"
        return "\(verb) [presentation id=\(id)] \(lesson.name) — \(who) on \(dayString(day))"
            + "\(timeSuffix(assignment))"
            + "\(repeatReceipt(purpose, conflicts: conflicts.count, of: students.count))."
    }

    /// The named children the record already covers — refusing the call when
    /// the caller has not said why the lesson is coming round again for them.
    private static func explainedConflicts(
        lesson: CDLesson,
        students: [CDStudent],
        on day: Date,
        purpose: RepeatPurpose?,
        index: PresentationRecordIndex
    ) throws -> [RepeatConflict] {
        let conflicts = repeatConflicts(
            lessonID: lesson.id?.uuidString ?? "", students: students, before: day, index: index
        )
        guard conflicts.isEmpty || purpose != nil else {
            throw refuseRepeat(
                tool: "schedule_presentation", lesson: lesson, conflicts: conflicts, of: students.count
            )
        }
        return conflicts
    }

    /// The same calendar `schedule_for_range` consults, so a plan is refused on
    /// exactly the days that tool reports as not in session — and in the words
    /// `schedule_meeting` refuses them.
    private static func requireSchoolDay(_ day: Date, in modelContext: NSManagedObjectContext) throws {
        guard SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext) else { return }
        throw MCPToolError(
            "School is not in session on \(dayString(day)) (\(weekdayName(day))); "
                + "nothing was scheduled. Choose a school day."
        )
    }

    // MARK: - Time of Day

    /// Puts the plan on a day, at the given time or — with none — into that
    /// day's morning half, which is what the in-app planner does.
    /// `schedule(for:)` is the same write the calendar's drag makes, so a time
    /// given here orders the day exactly as a drag would.
    private static func schedule(_ assignment: CDLessonAssignment, onDay day: Date, at time: TimeOfDay?) {
        guard let time else {
            assignment.schedule(onDay: day)
            return
        }
        let calendar = AppCalendar.shared
        let moment = calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: calendar.startOfDay(for: day)
        ) ?? calendar.startOfDay(for: day)
        assignment.schedule(for: moment, using: calendar)
    }

    /// " at 10:30", or " in the morning" — the receipt names when the plan
    /// landed, so a caller who passed a time can see it took, and one who did
    /// not can see which half of the day the lesson went into.
    private static func timeSuffix(_ assignment: CDLessonAssignment) -> String {
        whenText(assignment.scheduledFor)
    }

    struct TimeOfDay: Equatable {
        let hour: Int
        let minute: Int
    }

    /// Parses an optional HH:MM (24-hour) argument in the device's time zone —
    /// the school's, on the guide's Mac. Throws on anything else, since a
    /// silently ignored time would put a lesson in the wrong slot.
    static func timeArgument(_ arguments: [String: JSONValue], _ key: String) throws -> TimeOfDay? {
        guard let text = arguments[key]?.stringValue?.trimmed(), !text.isEmpty else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count <= 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else {
            throw MCPToolError("\(key) must be formatted HH:MM (24-hour), got \"\(text)\".")
        }
        return TimeOfDay(hour: hour, minute: minute)
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
            .filter { !$0.isPresented && Set($0.resolvedStudentIDs) == studentIDs }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .first
    }

    // MARK: - Rescheduling

    static func reschedulePresentationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "reschedule_presentation",
            title: "Reschedule Presentation",
            description: "Move a planned presentation to another day or time, or take it off the "
                + "calendar entirely (it returns to the planning list rather than being deleted). "
                + "Pass date alone to move it into that day's morning half, date and time to "
                + "place it at a time, or time alone to set a time on the day it already has. Presentations "
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
                        "description": .string("The new day, YYYY-MM-DD. Omit when unscheduling, or when only "
                            + "the time is changing.")
                    ],
                    "time": [
                        "type": "string",
                        "description": .string("Optional time of day, HH:MM (24-hour, in the school's local "
                            + "time zone). Without it a moved presentation lands in the morning half of "
                            + "its new day rather than at any particular time.")
                    ],
                    "unschedule": [
                        "type": "boolean",
                        "description": "Take the presentation off the calendar, back to the planning list"
                    ]
                ],
                "required": ["presentation_id"]
            ],
            annotations: .idempotentWrite,
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
        let time = try timeArgument(arguments, "time")

        let outcome: String
        if unschedule {
            assignment.unschedule()
            outcome = "\(title) is off the calendar and back in the planning list."
        } else if let day {
            schedule(assignment, onDay: day, at: time)
            outcome = "\(title) is now scheduled for \(dayString(day))\(timeSuffix(assignment))."
        } else if let time {
            // A time on its own keeps the day the plan already has.
            guard let current = assignment.scheduledFor else {
                throw MCPToolError(
                    "That presentation is not on the calendar, so a time alone has no day to go with. "
                        + "Pass a date as well."
                )
            }
            schedule(assignment, onDay: current, at: time)
            outcome = "\(title) stays on \(dayString(current)), now\(timeSuffix(assignment))."
        } else {
            throw MCPToolError("Pass a new date and/or time, or unschedule: true to take it off the calendar.")
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be rescheduled.")
        }
        return "[presentation id=\(id.uuidString)] \(outcome)"
    }
}
