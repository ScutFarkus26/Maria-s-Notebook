//
//  MCPNotebookTools+CurriculumMap.swift
//  Cosmic Daybook
//
//  The Three-Year View over MCP: one child across the whole plane, and one
//  lesson (or area) across the whole class. Both read the same
//  CurriculumMapEngine cells the screens draw, so "presented but never
//  chosen" means one thing in the app and in a conversation.
//
//  These are the tools to call for "what has Ora not had yet", "plan the
//  next month for Dalia", and "who has not had the distributive law" — the
//  last returns a set of names ready to hand to schedule_presentation.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Student Map

    static func studentCurriculumMapTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_curriculum_map",
            title: "Student Curriculum Map",
            description: "One child across the whole elementary cycle: the Great Lessons she has "
                + "heard, then every area with each lesson's state — not presented, presented, "
                + "chosen (work or practice followed), repeated, or mastered — with dates and the "
                + "latest recall outcome, and a closing list of areas untouched for the guide's "
                + "threshold. Call this for \"what has she not had yet\" or to plan her next month. "
                + "It reports records, never readiness.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, nickname, or id"
                    ],
                    "granularity": [
                        "type": "string",
                        "enum": ["area", "keyLesson", "allLessons"],
                        "description": .string("area: one line per area with counts. keyLesson (default): "
                            + "the milestones — hand-marked key lessons, the first lesson of every "
                            + "sub-area, and the Great Lesson stories. allLessons: every lesson.")
                    ],
                    "since": [
                        "type": "string",
                        "description": .string("YYYY-MM-DD. Only lessons with a presentation or other "
                            + "activity on or after this day; areas still list their totals.")
                    ]
                ],
                "required": ["student_name"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeStudentCurriculumMap(arguments: arguments, in: context())
            }
        )
    }

    private static func describeStudentCurriculumMap(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(try requireString(arguments, "student_name"), in: modelContext)
        guard let studentID = student.id else { throw MCPToolError("That student record has no identifier.") }
        let granularity = try granularityArgument(arguments)
        let since: Date? = try dayArgument(arguments, "since").map(AppCalendar.startOfDay)

        let input = CurriculumMapLoader.snapshot(in: modelContext)
        let cells = CurriculumMapEngine.cells(for: studentID, input: input)
        let settings = CurriculumMapSettings()
        let today = Date()
        let calendar = AppCalendar.shared
        let timeline = CurriculumTimeline.make(
            dateStarted: student.dateStarted,
            fallbackAnchor: cells.values.compactMap { $0.events.first?.date }.min(),
            today: today, zoom: .years, calendar: calendar
        )

        var lines: [String] = [studentHeadline(student, timeline: timeline)]
        lines.append(contentsOf: greatLessonLines(input: input, cells: cells))
        let shown = CurriculumMapEngine.lessons(input.lessons, at: granularity)
        var untouched: [String] = []
        for area in areasInOrder(input.lessons) {
            let areaLessons = input.lessons.filter { sameFiling($0.area, area) }
            let summary = CurriculumMapEngine.aggregate(
                areaLessons.compactMap { cells[$0.id] }, lessonCount: areaLessons.count
            )
            let days = settings.untouchedDays(for: area)
            let isUntouched = CurriculumMapEngine.isUntouched(
                lastPresented: summary.lastPresented, days: days, today: today, calendar: calendar
            )
            if isUntouched {
                let last = summary.lastPresented.map { "last presentation \(dayString($0))" } ?? "never presented"
                untouched.append("\(area) (\(last); flagged after \(days) days)")
            }
            lines.append("")
            lines.append(areaHeadline(area, summary: summary))
            guard granularity != .area else { continue }
            lines.append(contentsOf: areaLessonLines(
                shown.filter { sameFiling($0.area, area) }, cells: cells, since: since
            ))
        }
        lines.append("")
        lines.append(untouched.isEmpty
            ? "Untouched areas: none."
            : "Untouched areas (no presentation within the threshold): " + untouched.joined(separator: "; "))
        return lines.joined(separator: "\n")
    }

    /// One line per lesson in curriculum order; `since` keeps only lessons
    /// with activity on or after the day.
    private static func areaLessonLines(
        _ lessons: [CurriculumLessonRef], cells: [UUID: CurriculumCell], since: Date?
    ) -> [String] {
        let rows = lessons
            .filter { lesson in
                guard let since else { return true }
                guard let cell = cells[lesson.id], let activity = cell.lastActivity else { return false }
                return activity >= since
            }
            .sorted(by: curriculumOrder)
        guard !rows.isEmpty else {
            return [since.map { "  (nothing since \(dayString($0)))" } ?? "  (no key lessons filed)"]
        }
        return rows.map { lessonLine($0, cell: cells[$0.id]) }
    }

    private static func studentHeadline(_ student: CDStudent, timeline: CurriculumTimeline) -> String {
        let started = timeline.anchorIsEstimated
            ? "no start date on file — years counted from the first record"
            : "started \(dayString(timeline.anchor))"
        let id = student.id?.uuidString ?? "unknown"
        let year = CurriculumTimeline.yearBadge(timeline.currentYear)
        return "[student id=\(id)] \(student.fullName) — \(year) (\(started))"
    }

    private static func greatLessonLines(input: CurriculumMapInput, cells: [UUID: CurriculumCell]) -> [String] {
        let byRaw = CurriculumMapEngine.greatLessonLessons(in: input.lessons)
        var lines: [String] = ["", "Great Lessons:"]
        for great in GreatLesson.allCases {
            let stories = byRaw[great.rawValue] ?? []
            guard !stories.isEmpty else {
                lines.append("- \(great.displayName): no lesson tagged (tag the story in its lesson editor)")
                continue
            }
            let summary = CurriculumMapEngine.aggregate(stories.compactMap { cells[$0.id] }, lessonCount: stories.count)
            let names = stories.map(\.name).joined(separator: ", ")
            var detail = summary.state.toolName
            if let first = summary.firstPresented { detail += " \(dayString(first))" }
            lines.append("- \(great.displayName): \(detail) [\(names)]")
        }
        return lines
    }

    private static func areaHeadline(_ area: String, summary: CurriculumAggregate) -> String {
        var parts: [String] = ["\(summary.presentedCount) of \(summary.lessonCount) presented"]
        if let last = summary.lastPresented { parts.append("last presentation \(dayString(last))") }
        if let activity = summary.lastActivity { parts.append("last activity \(dayString(activity))") }
        return "\(area): " + parts.joined(separator: "; ")
    }

    private static func lessonLine(_ lesson: CurriculumLessonRef, cell: CurriculumCell?) -> String {
        let filing = lesson.sequence.isEmpty ? "" : " (\(lesson.sequence))"
        guard let cell else {
            return "- [lesson id=\(lesson.id.uuidString)] \(lesson.name)\(filing) — notPresented"
        }
        var parts: [String] = [cell.state.toolName]
        if cell.isConfirmed, cell.state < .mastered { parts.append("confirmed ready for next") }
        if let first = cell.firstPresented { parts.append("presented \(dayString(first))") }
        if let last = cell.lastPresented, last != cell.firstPresented { parts.append("again \(dayString(last))") }
        if !cell.evidence.workIDs.isEmpty { parts.append("\(cell.evidence.workIDs.count) work") }
        if cell.practiceCount > 0 { parts.append("\(cell.practiceCount) practice") }
        if let recall = cell.recall { parts.append("recall \(recall.rawValue)") }
        if let activity = cell.lastActivity { parts.append("last activity \(dayString(activity))") }
        return "- [lesson id=\(lesson.id.uuidString)] \(lesson.name)\(filing) — " + parts.joined(separator: "; ")
    }

    // MARK: - Class Map

    static func classCurriculumMapTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "class_curriculum_map",
            title: "Class Curriculum Map",
            description: "Every enrolled child's state on one lesson — or their best state in one "
                + "area — grouped by state and ordered by enrollment year, so \"who has not had the "
                + "distributive law\" comes back as names ready for schedule_presentation. Pass a "
                + "lesson name or id, or an area name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson_or_area": [
                        "type": "string",
                        "description": .string("A lesson name or id (from find_lessons), or a top-level "
                            + "area such as \"Biology\"")
                    ],
                    "state": [
                        "type": "string",
                        "enum": ["notPresented", "presented", "chosen", "repeated", "mastered"],
                        "description": "Only the children in this state"
                    ]
                ],
                "required": ["lesson_or_area"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeClassCurriculumMap(arguments: arguments, in: context())
            }
        )
    }

    private static func describeClassCurriculumMap(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "lesson_or_area")
        let filter: CurriculumCellState? = try stateArgument(arguments)
        let input = CurriculumMapLoader.snapshot(in: modelContext)
        let hidden = TestStudentsFilter.normalizedHiddenNames()
        let students = input.students
            .filter { $0.isEnrolled && !hidden.contains($0.fullName.normalizedForComparison()) }
            .sorted(by: enrollmentOrder)
        guard !students.isEmpty else { return "No enrolled students." }

        let (title, lessonIDs) = try resolveMapScope(reference, lessons: input.lessons, in: modelContext)
        // Only the lesson (or area) asked about: the same cells the whole grid
        // holds for it, without finalising every other (child, lesson) pair.
        let all = CurriculumMapEngine.cells(input: input, lessons: Set(lessonIDs))
        let today = Date()
        let calendar = AppCalendar.shared

        var byState: [CurriculumCellState: [String]] = [:]
        for student in students {
            let cells = lessonIDs.compactMap { all[student.id]?[$0] }
            let summary = CurriculumMapEngine.aggregate(cells, lessonCount: lessonIDs.count)
            let year = student.dateStarted.map { started in
                let number = CurriculumTimeline.enrollmentYear(anchor: started, on: today, calendar: calendar)
                return CurriculumTimeline.yearBadge(number)
            } ?? "year unknown"
            var line = "[student id=\(student.id.uuidString)] \(student.fullName) (\(year)"
            if let last = summary.lastPresented { line += ", last presentation \(dayString(last))" }
            if let recall = summary.recall { line += ", recall \(recall.rawValue)" }
            line += ")"
            byState[summary.state, default: []].append(line)
        }

        var lines: [String] = ["\(title) — \(students.count) enrolled child(ren):"]
        for state in CurriculumCellState.allCases.reversed() where filter == nil || filter == state {
            let names = byState[state] ?? []
            lines.append("")
            lines.append("\(state.label) (\(names.count)):")
            lines.append(contentsOf: names.isEmpty ? ["  none"] : names.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    /// A lesson reference first; failing that, an area name.
    private static func resolveMapScope(
        _ reference: String, lessons: [CurriculumLessonRef], in modelContext: NSManagedObjectContext
    ) throws -> (title: String, lessonIDs: [UUID]) {
        if let lesson = try? resolveLessonReference(reference, in: modelContext), let id = lesson.id {
            return (describeLesson(lesson), [id])
        }
        let areas = areasInOrder(lessons)
        guard let area = areas.first(where: { sameFiling($0, reference) }) else {
            throw MCPToolError(
                "\"\(reference)\" is neither a lesson nor an area. Use find_lessons for a lesson; "
                    + "areas are: \(areas.joined(separator: ", "))."
            )
        }
        return ("\(area) (best state across the area)", lessons.filter { sameFiling($0.area, area) }.map(\.id))
    }

    // MARK: - Arguments & Ordering

    private static func granularityArgument(_ arguments: [String: JSONValue]) throws -> CurriculumGranularity {
        guard let raw = nonEmpty(arguments["granularity"]?.stringValue) else { return .keyLessons }
        guard let granularity = CurriculumGranularity(rawValue: raw) else {
            throw MCPToolError("granularity must be one of: area, keyLesson, allLessons. Got \"\(raw)\".")
        }
        return granularity
    }

    private static func stateArgument(_ arguments: [String: JSONValue]) throws -> CurriculumCellState? {
        guard let raw = nonEmpty(arguments["state"]?.stringValue) else { return nil }
        guard let state = CurriculumCellState(toolName: raw) else {
            let allowed = CurriculumCellState.allCases.map(\.toolName).joined(separator: ", ")
            throw MCPToolError("state must be one of: \(allowed). Got \"\(raw)\".")
        }
        return state
    }

    private static func areasInOrder(_ lessons: [CurriculumLessonRef]) -> [String] {
        let unique = Set(lessons.map(\.area).filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadAreaOrder(existing: existing)
    }

    private static func curriculumOrder(_ lhs: CurriculumLessonRef, _ rhs: CurriculumLessonRef) -> Bool {
        if !sameFiling(lhs.sequence, rhs.sequence) {
            return lhs.sequence.localizedCaseInsensitiveCompare(rhs.sequence) == .orderedAscending
        }
        return CurriculumMapEngine.precedes(lhs, rhs)
    }

    /// Longest-enrolled first, so the cohorts read as bands; name within a cohort.
    private static func enrollmentOrder(_ lhs: CurriculumStudentRef, _ rhs: CurriculumStudentRef) -> Bool {
        switch (lhs.dateStarted, rhs.dateStarted) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default: return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }
}
