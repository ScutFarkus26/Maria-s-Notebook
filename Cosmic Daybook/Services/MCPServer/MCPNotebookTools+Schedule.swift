//
//  MCPNotebookTools+Schedule.swift
//  Cosmic Daybook
//
//  What the classroom's days look like: lessons planned, work checks due,
//  calendar events, and the days school isn't in session.
//
//  The reads mirror TodayDataFetcher's predicates so a day described over
//  MCP matches the Today view exactly — including its use of `scheduledFor`
//  (not `scheduledForDay`) for the day window.
//
//  Scheduling and rescheduling live in MCPNotebookTools+ScheduleWrites.swift.
//  The shared output formatting below is used by every domain's tools.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Reading the Schedule

    static func scheduleForRangeTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "schedule_for_range",
            title: "Schedule",
            description: "The classroom's plan for a day or a span of days: lessons scheduled to "
                + "be presented, work check-ins due, calendar events, and whether school is in "
                + "session. Use this for what is coming up; student_presentation_history covers "
                + "what has already been given.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "start_date": [
                        "type": "string",
                        "description": "First day, YYYY-MM-DD (default today)"
                    ],
                    "end_date": [
                        "type": "string",
                        "description": .string("Last day, YYYY-MM-DD, inclusive (default the same "
                            + "as start_date). At most 60 days are returned.")
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "Optional — show only what involves this student"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let start = AppCalendar.startOfDay(try dayArgument(arguments, "start_date") ?? Date())
                let requestedEnd = AppCalendar.startOfDay(
                    try dayArgument(arguments, "end_date") ?? start
                )
                guard requestedEnd >= start else {
                    throw MCPToolError("end_date must be on or after start_date.")
                }
                let student = try nonEmpty(arguments["student_name"]?.stringValue)
                    .map { try resolveStudentReference($0, in: modelContext) }
                return describeSchedule(
                    from: start, through: requestedEnd, student: student, in: modelContext
                )
            }
        )
    }

    /// One day's plan, assembled from the four sources the Today view reads.
    private struct ScheduledDay {
        let day: Date
        let isNonSchoolDay: Bool
        let presentations: [CDLessonAssignment]
        let checkIns: [CDWorkCheckIn]
        let events: [CDCalendarEvent]
        let notes: [CDCalendarNote]

        var isEmpty: Bool {
            presentations.isEmpty && checkIns.isEmpty && events.isEmpty && notes.isEmpty
        }
    }

    private static func describeSchedule(
        from start: Date, through end: Date, student: CDStudent?,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let calendar = AppCalendar.shared
        let span = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let dayCount = min(max(span, 1), maximumScheduleDays)
        let days = (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }.map { day in
            scheduledDay(day, student: student, in: modelContext)
        }

        let described = days.filter { !$0.isEmpty || $0.isNonSchoolDay }
        guard !described.isEmpty else {
            let who = student.map { " involving \($0.fullName)" } ?? ""
            return "Nothing is scheduled\(who) between \(dayString(start)) and \(dayString(end))."
        }

        var sections = described.map { describe($0, in: modelContext) }
        if span > maximumScheduleDays {
            sections.append(
                "(Range truncated to \(maximumScheduleDays) days — ask again from "
                    + "\(dayString(days.last.map { $0.day.addingTimeInterval(86_400) } ?? end)) "
                    + "for the rest.)"
            )
        }
        return sections.joined(separator: "\n\n")
    }

    private static func scheduledDay(
        _ day: Date, student: CDStudent?, in modelContext: NSManagedObjectContext
    ) -> ScheduledDay {
        let nextDay = AppCalendar.shared.date(byAdding: .day, value: 1, to: day) ?? day
        let studentID = student?.id

        let presentations = TodayDataFetcher
            .fetchLessons(day: day, nextDay: nextDay, context: modelContext)
            .filter { !$0.isPresented }
            .filter { assignment in
                guard let studentID else { return true }
                return assignment.studentUUIDs.contains(studentID)
            }

        let checkInRequest = CDFetchRequest(CDWorkCheckIn.self)
        checkInRequest.predicate = NSPredicate(
            format: "date >= %@ AND date < %@", day as NSDate, nextDay as NSDate
        )
        checkInRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: true)
        ]
        // `resolvedWork` reads the relationship or the workID string, so a
        // check-in dropped onto the week plan before the relationship was
        // always set still names its work here.
        let checkIns = modelContext.safeFetch(checkInRequest).filter { checkIn in
            guard let studentID else { return true }
            return checkIn.resolvedWork(in: modelContext).map { involves(studentID, in: $0) } ?? false
        }

        // Calendar events and day notes belong to the classroom as a whole, so a
        // student filter hides them rather than pretending they are about one child.
        let events = studentID == nil
            ? TodayDataFetcher.fetchCalendarEvents(day: day, nextDay: nextDay, context: modelContext)
            : []
        let notes = studentID == nil ? calendarNotes(on: day, in: modelContext) : []

        return ScheduledDay(
            day: day,
            isNonSchoolDay: SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext),
            presentations: presentations,
            checkIns: checkIns,
            events: events,
            notes: notes
        )
    }

    private static func describe(
        _ day: ScheduledDay, in modelContext: NSManagedObjectContext
    ) -> String {
        var lines = ["\(dayString(day.day)) (\(weekdayName(day.day)))"]
        if day.isNonSchoolDay {
            lines.append("  School is not in session.")
        }

        if !day.presentations.isEmpty {
            lines.append("  Presentations planned:")
            lines.append(contentsOf: day.presentations.map { assignment in
                let id = assignment.id?.uuidString ?? "unknown"
                let title = nonEmpty(assignment.lessonTitleSnapshot)
                    ?? assignment.lesson?.name ?? "Lesson"
                let who = studentNames(for: assignment.studentUUIDs, in: modelContext)
                let when = whenText(assignment.scheduledFor)
                return "    - [presentation id=\(id)] \(title)\(when) — \(who)"
            })
        }

        if !day.checkIns.isEmpty {
            lines.append("  Work check-ins due:")
            lines.append(contentsOf: day.checkIns.map { checkIn in
                let work = checkIn.resolvedWork(in: modelContext)
                let id = work?.id?.uuidString ?? "unknown"
                let title = nonEmpty(work?.title) ?? "Untitled work"
                // No work row at all means the check-in outlived its work; say
                // so rather than printing it as an unassigned plan.
                let who = work.map { workStudentNames(for: $0, in: modelContext) }
                    ?? "orphaned check-in, its work no longer exists"
                let purpose = nonEmpty(checkIn.purpose).map { " — \($0)" } ?? ""
                return "    - [work id=\(id)] \(title) — \(who) (\(checkIn.status.rawValue.lowercased()))\(purpose)"
            })
        }

        if !day.events.isEmpty {
            lines.append("  Calendar:")
            lines.append(contentsOf: day.events.map { event in
                let id = event.id?.uuidString ?? "unknown"
                let when = event.isAllDay
                    ? "all day"
                    : "\(timeString(event.startDate))–\(timeString(event.endDate))"
                let place = nonEmpty(event.location).map { " @ \($0)" } ?? ""
                return "    - [event id=\(id)] \(when) \(event.title)\(place)"
            })
        }

        if !day.notes.isEmpty {
            lines.append("  Day notes:")
            lines.append(contentsOf: day.notes.map { "    - \($0.text.trimmed())" })
        }

        return lines.joined(separator: "\n")
    }

    /// Perpetual-calendar notes are stored as year/month/day integers rather
    /// than a Date, so they are matched on components instead of a range.
    private static func calendarNotes(
        on day: Date, in modelContext: NSManagedObjectContext
    ) -> [CDCalendarNote] {
        let parts = AppCalendar.shared.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else {
            return []
        }
        let request = CDFetchRequest(CDCalendarNote.self)
        request.predicate = NSPredicate(
            format: "year == %d AND month == %d AND day == %d", year, month, dayOfMonth
        )
        return modelContext.safeFetch(request).filter { !$0.text.trimmed().isEmpty }
    }

    // MARK: - Shared Formatting

    /// A guide asking for "this term" should get a useful answer rather than a
    /// wall of empty days; beyond this the tool says where to resume.
    static let maximumScheduleDays = 60

    /// Trimmed text, or nil when there was nothing but whitespace — so an empty
    /// snapshot title falls through to the next fallback instead of printing blank.
    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmed(), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static let isoTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func timeString(_ date: Date?) -> String {
        date.map { isoTime.string(from: $0) } ?? "—"
    }

    /// How a presentation's `scheduledFor` should be spoken.
    ///
    /// A scheduled presentation usually has no time: the guide plans an order
    /// within a half of the day, and that order is encoded as seconds past the
    /// half's base hour. Printed as a clock, every such row reads "at 09:00" —
    /// a time nobody set, and one that buries the only thing the date really
    /// says. So say the half, and give a clock time only when one was set.
    ///
    /// Returns a suffix, empty for an unscheduled plan, so it appends to a
    /// sentence that has just named the day.
    static func whenText(_ date: Date?) -> String {
        guard let date else { return "" }
        switch DayHalfPlanner.moment(of: date) {
        case .half(.morning): return " in the morning"
        case .half(.afternoon): return " in the afternoon"
        case .time(let moment): return " at \(timeString(moment))"
        }
    }

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func weekdayName(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    /// Resolves student ids to names for output, quietly skipping ids whose
    /// student record is gone — a stale id should not blank out the whole line.
    /// A former student is named with her status, so a work item that still
    /// carries her reads as what it is rather than as a roster the reader
    /// cannot find in list_students.
    static func studentNames(
        for ids: [UUID], in modelContext: NSManagedObjectContext
    ) -> String {
        let repository = StudentRepository(context: modelContext)
        let names = ids.compactMap { id -> String? in
            guard let student = repository.fetchStudent(id: id) else { return nil }
            return student.isEnrolled ? student.fullName : "\(student.fullName) (\(student.enrollmentStatusRaw))"
        }.sorted()
        return names.isEmpty ? "no students linked" : names.joined(separator: ", ")
    }

    /// Everyone attached to a work item: its owner plus any co-participants.
    static func workStudentNames(
        for work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) -> String {
        studentNames(for: workStudentIDs(for: work), in: modelContext)
    }

    static func workStudentIDs(for work: CDWorkModel) -> [UUID] {
        WorkGrouping.studentIDs(of: work)
    }

    static func involves(_ studentID: UUID, in work: CDWorkModel) -> Bool {
        WorkGrouping.involves(studentID, in: work)
    }
}
