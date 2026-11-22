//
//  MCPNotebookTools+Unrecorded.swift
//  Cosmic Daybook
//
//  `schedule_for_range` › `unrecorded`: what is still open from the days just
//  gone, for the end-of-day chat (plan "Cut unused features and close the
//  lesson loop", 2026-11-21). Lessons planned and never recorded used to sit
//  as "planned" for days with nothing pointing at them.
//
//  Day by day it lists the plans not given, with each child's open-practice
//  line; the quick notes still tagged "to fill in"; and days with an all-day
//  "No School" event that the school calendar still counts as in session (the
//  app's school-day rule doesn't read calendar events, so it says which call
//  fixes the day). It closes with the calls that settle each item.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// School days the view looks back over when no dates are given, today included.
    static let unrecordedSchoolDays = 14

    static func unrecordedTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "unrecorded",
            title: "Unrecorded",
            description: "What is still open from the days just gone, day by day: lessons planned and "
                + "not recorded (with their children, and any child still practicing an earlier lesson "
                + "in the sequence), quick notes tagged \"to fill in\", and days with a \"No School\" "
                + "calendar event that the school calendar counts as in session. Ends with the calls "
                + "that settle each item. Without dates it covers the last 14 school days through today.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "start_date": [
                        "type": "string",
                        "description": "First day, YYYY-MM-DD (default 14 school days back, counting today)"
                    ],
                    "end_date": [
                        "type": "string",
                        "description": "Last day, YYYY-MM-DD, inclusive (default today). At most 60 days are read."
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let today = AppCalendar.startOfDay(Date())
                let end = AppCalendar.startOfDay(try dayArgument(arguments, "end_date") ?? today)
                let start = AppCalendar.startOfDay(
                    try dayArgument(arguments, "start_date")
                        ?? schoolDaysBack(unrecordedSchoolDays, through: end, in: modelContext)
                )
                guard end >= start else {
                    throw MCPToolError("end_date must be on or after start_date.")
                }
                return describeUnrecorded(from: start, through: end, in: modelContext)
            }
        )
    }

    /// The first of the last `count` school days up to and including `end`.
    static func schoolDaysBack(_ count: Int, through end: Date, in modelContext: NSManagedObjectContext) -> Date {
        var cursor = AppCalendar.startOfDay(end)
        var found = SchoolDayChecker.isSchoolDay(cursor, using: modelContext) ? 1 : 0
        while found < count {
            guard let previous = SchoolDayChecker.schoolDay(from: cursor, forward: false, using: modelContext)
            else { break }
            cursor = previous
            found += 1
        }
        return cursor
    }

    /// One day's open items.
    private struct OpenDay {
        let day: Date
        let plans: [CDLessonAssignment]
        let notes: [CDNote]
        /// Titles of the day's all-day "No School" events, when the school
        /// calendar counts the day in session.
        let noSchoolEvents: [String]

        var isEmpty: Bool { plans.isEmpty && notes.isEmpty && noSchoolEvents.isEmpty }
    }

    static func describeUnrecorded(
        from start: Date, through end: Date, in modelContext: NSManagedObjectContext
    ) -> String {
        let calendar = AppCalendar.shared
        let span = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let dayCount = min(max(span, 1), maximumScheduleDays)
        let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        guard let last = days.last, let after = calendar.date(byAdding: .day, value: 1, to: last) else {
            return "Nothing is open between \(dayString(start)) and \(dayString(end))."
        }

        let plans = unrecordedPlans(from: start, before: after, in: modelContext)
        let notes = QuickNote.waiting(from: start, before: after, in: modelContext)
        let open = days.map { day in
            OpenDay(
                day: day,
                plans: plans.filter { $0.scheduledFor.map { calendar.isDate($0, inSameDayAs: day) } ?? false },
                notes: notes.filter { $0.createdAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false },
                noSchoolEvents: noSchoolEventsInSession(on: day, in: modelContext)
            )
        }.filter { !$0.isEmpty }

        guard !open.isEmpty else {
            return "Nothing is open between \(dayString(start)) and \(dayString(last)): every planned "
                + "lesson is recorded and no quick note is waiting."
        }

        let sequences = WorkToShowFirst.Sequences(lessons: DataQueryService(context: modelContext).fetchAllLessons())
        var sections = ["Still open from \(dayString(start)) through \(dayString(last)):"]
        sections += open.map { describe($0, sequences: sequences, in: modelContext) }
        sections.append(settlingCalls(open))
        if span > maximumScheduleDays {
            sections.append("(Range truncated to \(maximumScheduleDays) days.)")
        }
        return sections.joined(separator: "\n\n")
    }

    /// Plans on a day in [start, end) not given, earliest first.
    private static func unrecordedPlans(
        from start: Date, before end: Date, in modelContext: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "scheduledFor >= %@ AND scheduledFor < %@", start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledFor, ascending: true)]
        return modelContext.safeFetch(request).filter { !$0.isDeleted && !$0.isGiven }
    }

    /// The day's all-day events whose title says "No School", when school
    /// is counted in session that day.
    private static func noSchoolEventsInSession(on day: Date, in modelContext: NSManagedObjectContext) -> [String] {
        guard !SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext),
              let next = AppCalendar.shared.date(byAdding: .day, value: 1, to: day) else { return [] }
        return TodayDataFetcher.fetchCalendarEvents(day: day, nextDay: next, context: modelContext)
            .filter { $0.isAllDay && $0.title.range(of: "no school", options: [.caseInsensitive]) != nil }
            .map { $0.title.trimmed() }
    }

    private static func describe(
        _ open: OpenDay, sequences: WorkToShowFirst.Sequences, in modelContext: NSManagedObjectContext
    ) -> String {
        var lines = ["\(dayString(open.day)) (\(weekdayName(open.day)))"]
        if !open.plans.isEmpty {
            lines.append("  Planned, not recorded:")
            for plan in open.plans {
                let id = plan.id?.uuidString ?? "unknown"
                let title = nonEmpty(plan.lessonTitleSnapshot) ?? plan.lesson?.name ?? "Lesson"
                let who = shortNames(plan.resolvedStudentIDs, in: modelContext)
                lines.append("    - [presentation id=\(id)] \(title) — \(who)")
                let warnings = practiceWarningLines(
                    lessonID: plan.resolvedLessonID.uuidString, studentIDs: plan.resolvedStudentIDs,
                    sequences: sequences, in: modelContext
                )
                lines += warnings.map { "      \($0)" }
            }
        }
        if !open.notes.isEmpty {
            lines.append("  Quick notes to fill in:")
            for note in open.notes {
                let about = noteContext(note, in: modelContext)
                lines.append("    - [note id=\(citationID(note.id))] \"\(note.body.trimmed())\"\(about)")
            }
        }
        for title in open.noSchoolEvents {
            lines.append("  The calendar says \"\(title)\", but the school calendar counts this day in "
                + "session. If school was out, call set_school_days with date \(dayString(open.day)).")
        }
        return lines.joined(separator: "\n")
    }

    /// " — Ora L, Maya S (Golden Beads)": who the note is about and its lesson.
    private static func noteContext(_ note: CDNote, in modelContext: NSManagedObjectContext) -> String {
        let who: String = switch note.scope {
        case .all: "the class"
        case .student(let id): shortNames([id], in: modelContext)
        case .students(let ids): shortNames(ids, in: modelContext)
        }
        let lesson = note.lessonAssignment.flatMap { nonEmpty($0.lessonTitleSnapshot) ?? $0.lesson?.name }
        return " — \(who)" + (lesson.map { " (\($0))" } ?? "")
    }

    /// The calls that settle what was listed.
    private static func settlingCalls(_ open: [OpenDay]) -> String {
        var lines = ["To settle these:"]
        if open.contains(where: { !$0.plans.isEmpty }) {
            lines.append("- Given: record_presentation with planned_presentation_id and student_names (who was "
                + "there; a child on the plan who wasn't stays planned), plus what the guide says about each child.")
            lines.append("- Moved: reschedule_presentation with presentation_id and the new date.")
            lines.append("- Not given and not wanted: discard_presentation with presentation_id and confirm: true.")
        }
        if open.contains(where: { !$0.notes.isEmpty }) {
            lines.append("- A quick note: update_observation with note_id and the fuller body (that takes "
                + "the \"\(QuickNote.tagName)\" tag off).")
        }
        if open.contains(where: { !$0.noSchoolEvents.isEmpty }) {
            lines.append("- A day school was out: set_school_days with that date.")
        }
        return lines.joined(separator: "\n")
    }
}
