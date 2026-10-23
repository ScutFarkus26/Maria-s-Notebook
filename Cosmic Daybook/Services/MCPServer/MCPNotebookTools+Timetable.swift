//
//  MCPNotebookTools+Timetable.swift
//  Cosmic Daybook
//
//  The Schedules timetables, read: the lanes (two rooms and two people) with
//  their weekly blocks, and any one day worked out by `ScheduleDayResolver`.
//  The writes are in +TimetableWrites. MCP is the guide's own, so the day
//  names the lessons; the Daybook Assistant never sees them.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Weekly Schedules

    static func weeklySchedulesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "weekly_schedules",
            title: "Weekly Schedules",
            description: "The Schedules timetables: the lanes (our class and the adolescent room are rooms; "
                + "the guide and Morah Devora are people) and each lane's weekly blocks by weekday, time, "
                + "teacher and children. Pass date to see that one day worked out instead: the blocks that "
                + "apply, that day's changes (cancelled, changed, one-offs, who is out), the guide's "
                + "planned lessons by name (all-adolescent lessons sit inside his turn in the adolescent "
                + "room), and gentle warnings. Block ids shown here are what change_schedule_day takes.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lane": [
                        "type": "string",
                        "description": "Only this lane, by name or id"
                    ],
                    "weekday": [
                        "type": "string",
                        "enum": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
                        "description": "Only blocks on this weekday (ignored with date)"
                    ],
                    "date": [
                        "type": "string",
                        "description": "Show this day worked out, YYYY-MM-DD"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeTimetable(arguments: arguments, in: context())
            }
        )
    }

    private static func describeTimetable(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lanes = TimetableService.lanes(in: modelContext)
        guard !lanes.isEmpty else {
            return "No timetable is set up yet. set_timetable enters a lane's week."
        }
        let only = try nonEmpty(arguments["lane"]?.stringValue).map { try timetableLane($0, in: lanes) }
        if let day = try dayArgument(arguments, "date") {
            return describeScheduleDay(day, only: only, in: modelContext)
        }
        let weekday = try nonEmpty(arguments["weekday"]?.stringValue).map(parseWeekday)
        return describeWeeks(of: only.map { [$0] } ?? lanes, weekday: weekday, lanes: lanes, in: modelContext)
    }

    // MARK: Weeks

    private static func describeWeeks(
        of shown: [CDTimetableLane], weekday: Weekday?, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) -> String {
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: Date())
        let names = studentNameIndex(in: modelContext)
        var sections: [String] = []
        for lane in shown {
            let blocks = TimetableService.blocks(of: lane, in: modelContext).filter { block in
                if block.isOneOff { return (block.onDay ?? .distantPast) >= today && weekday == nil }
                guard TimetableService.isRunning(block, onOrAfter: today, calendar: calendar) else { return false }
                return weekday == nil || block.weekday == weekday
            }
            var lines = ["[lane id=\(lane.id?.uuidString ?? "unknown")] \(laneLabel(lane))"]
            if blocks.isEmpty {
                lines.append("  (no blocks\(weekday.map { " on \($0.rawValue)" } ?? ""))")
            }
            for day in Weekday.allCases {
                let mine = blocks.filter { !$0.isOneOff && $0.weekday == day }
                guard !mine.isEmpty else { continue }
                lines.append("  \(day.rawValue)")
                lines.append(contentsOf: mine.sorted(by: blockFirst).map {
                    "    - " + weeklyLine($0, lanes: lanes, names: names)
                })
            }
            let oneOffs = blocks.filter(\.isOneOff).sorted { ($0.onDay ?? .distantPast) < ($1.onDay ?? .distantPast) }
            if !oneOffs.isEmpty {
                lines.append("  One-offs")
                lines.append(contentsOf: oneOffs.map { "    - " + weeklyLine($0, lanes: lanes, names: names) })
            }
            sections.append(lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func weeklyLine(
        _ block: CDTimetableBlock, lanes: [CDTimetableLane], names: [String: String]
    ) -> String {
        var line = ""
        if let onDay = block.onDay { line += "\(weekdayName(onDay)) \(dayString(onDay)) " }
        line += TimetableDay.rangeText(block.values) + " " + titleText(block.values)
        line += " [block id=\(block.id?.uuidString ?? "unknown")]"
        line += detailText(block.values, lanes: lanes, names: names)
        if let from = block.validFrom, from > AppCalendar.shared.startOfDay(for: Date()) {
            line += " (from \(dayString(from)))"
        }
        if let until = block.validUntil { line += " (until \(dayString(until)))" }
        return line
    }

    private static func blockFirst(_ lhs: CDTimetableBlock, _ rhs: CDTimetableBlock) -> Bool {
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }

    // MARK: A day

    private static func describeScheduleDay(
        _ requested: Date, only: CDTimetableLane?, in modelContext: NSManagedObjectContext
    ) -> String {
        let calendar = AppCalendar.shared
        let day = calendar.startOfDay(for: requested)
        let heading = "\(weekdayName(day)) \(dayString(day))"
        let resolved = resolveScheduleDay(day, in: modelContext)
        guard resolved.isSchoolDay else { return "\(heading): no school." }

        let laneRows = TimetableService.lanes(in: modelContext)
        let names = studentNameIndex(in: modelContext)
        var sections = [resolved.changeCount == 0
            ? heading
            : "\(heading) — \(resolved.changeCount) change\(resolved.changeCount == 1 ? "" : "s") today"]
        for lane in resolved.lanes where only == nil || lane.lane.id == only?.id {
            var lines = ["[lane id=\(lane.lane.id.uuidString)] \(lane.lane.name)"
                + (lane.isOut ? " — out today" : "")]
            if lane.items.isEmpty { lines.append("  (nothing)") }
            for item in lane.items {
                lines.append(contentsOf: itemLines(item, in: resolved, lanes: laneRows, names: names))
            }
            sections.append(lines.joined(separator: "\n"))
        }
        let warnings = resolved.warnings.map { warning in
            "  - " + warning.text(name: { names[$0.uppercased()] })
        }
        if !warnings.isEmpty { sections.append((["Warnings"] + warnings).joined(separator: "\n")) }
        return sections.joined(separator: "\n\n")
    }

    /// The day worked out from the store, with the lessons' names.
    static func resolveScheduleDay(_ day: Date, in modelContext: NSManagedObjectContext) -> ScheduleDay {
        let calendar = AppCalendar.shared
        let timetable = TimetableService.timetable(from: day, through: day, in: modelContext, calendar: calendar)
        let isSchoolDay = !SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext)
        return ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: day,
            lanes: timetable.lanes,
            blocks: timetable.blocks,
            changes: timetable.changes,
            lessons: ScheduleLessonPlan.lessons(on: day, in: modelContext, calendar: calendar),
            studentLevels: ScheduleLessonPlan.studentLevels(in: modelContext),
            isSchoolDay: isSchoolDay,
            calendar: calendar
        ))
    }

    private static func itemLines(
        _ item: ScheduleDay.Item, in day: ScheduleDay, lanes: [CDTimetableLane], names: [String: String]
    ) -> [String] {
        switch item.kind {
        case .block(let block):
            return ["  - " + dayBlockLine(block, prefix: "", in: day, lanes: lanes, names: names)]
                + lessonLines(block.lessons, indent: "      ", names: names)
        case .turn(let block):
            let room = day.lane(block.laneID)?.lane.name ?? "a room"
            return ["  - " + dayBlockLine(block, prefix: "In \(room): ", in: day, lanes: lanes, names: names)]
                + lessonLines(block.lessons, indent: "      ", names: names)
        case .lesson(let lesson):
            return lessonLines([lesson], indent: "  - ", names: names)
        case .halfList(let half, let lessons):
            return ["  - \(half.rawValue.capitalized) lessons, in order"]
                + lessonLines(lessons, indent: "      ", names: names)
        }
    }

    private static func dayBlockLine(
        _ block: ScheduleDay.Block, prefix: String, in day: ScheduleDay, lanes: [CDTimetableLane],
        names: [String: String]
    ) -> String {
        var line = prefix + TimetableDay.rangeText(block.values) + " " + titleText(block.values)
        line += " [block id=\(block.id.uuidString)]"
        line += detailText(block.values, lanes: lanes, names: names)
        if block.isOneOff { line += " (one-off)" } else if block.isChanged { line += " (changed today)" }
        if block.teacherIsOut { line += " — out" }
        return line
    }

    private static func lessonLines(
        _ lessons: [ScheduleDay.Lesson], indent: String, names: [String: String]
    ) -> [String] {
        lessons.map { lesson in
            let snapshot = lesson.snapshot
            var line = indent + (snapshot.minute.map { TimetableDay.clockText($0) + " " } ?? "")
            line += snapshot.title.flatMap(nonEmpty) ?? "A lesson"
            line += " [presentation id=\(snapshot.id.uuidString)]"
            let kids = children(snapshot.studentIDs, names: names)
            if !kids.isEmpty { line += " — " + kids }
            if let note = lesson.note { line += " (\(note))" }
            return line
        }
    }

    // MARK: Text

    private static func laneLabel(_ lane: CDTimetableLane) -> String {
        "\(lane.name) — \(lane.kind.rawValue)" + (lane.isGuide ? ", the guide" : "")
    }

    private static func titleText(_ values: TimetableBlockValues) -> String {
        nonEmpty(values.title) ?? "Untitled"
    }

    /// " — taught by Morah Devora — with Maya Soto, Eli Ross — note".
    private static func detailText(
        _ values: TimetableBlockValues, lanes: [CDTimetableLane], names: [String: String]
    ) -> String {
        var text = ""
        let teacher = values.teacherLaneID.flatMap { id in lanes.first { $0.id == id }?.name }
            ?? nonEmpty(values.teacherName)
        if let teacher { text += " — taught by \(teacher)" }
        let kids = children(values.studentIDs, names: names)
        if !kids.isEmpty { text += " — with \(kids)" }
        if let note = nonEmpty(values.note) { text += " — \(note)" }
        return text
    }

    private static func children(_ ids: [String], names: [String: String]) -> String {
        ids.map { names[$0.uppercased()] ?? "a child no longer in the notebook" }.joined(separator: ", ")
    }

    // MARK: - Shared with the writes

    /// The lanes a reference could mean: by id, else by exact name, else by a
    /// name that contains what was typed ("Devora" finds "Morah Devora").
    static func matchingTimetableLanes(_ reference: String, in lanes: [CDTimetableLane]) -> [CDTimetableLane] {
        if let id = UUID(uuidString: reference), let lane = lanes.first(where: { $0.id == id }) { return [lane] }
        let key = reference.foldedKey()
        let exact = lanes.filter { $0.name.foldedKey() == key }
        if !exact.isEmpty { return exact }
        return lanes.filter { !key.isEmpty && $0.name.foldedKey().contains(key) }
    }

    /// One lane by id or name. Ambiguity and misses throw.
    static func timetableLane(_ reference: String, in lanes: [CDTimetableLane]) throws -> CDTimetableLane {
        let matches = matchingTimetableLanes(reference, in: lanes)
        if matches.count == 1, let lane = matches.first { return lane }
        let known = lanes.map(\.name).joined(separator: ", ")
        if matches.isEmpty {
            throw MCPToolError("No lane named \"\(reference)\". The lanes are: \(known).")
        }
        throw MCPToolError("More than one lane matches \"\(reference)\": \(known). Use the full name.")
    }

    /// "Monday", "mon", "Fri": a weekday by full name or its first three letters.
    static func parseWeekday(_ text: String) throws -> Weekday {
        let key = text.foldedKey()
        if let day = Weekday.allCases.first(where: { $0.rawValue.lowercased() == key })
            ?? Weekday.allCases.first(where: { key.count == 3 && $0.rawValue.lowercased().hasPrefix(key) }) {
            return day
        }
        throw MCPToolError("\"\(text)\" is not a weekday. Use a name like Monday.")
    }

    /// A time of day as minutes after midnight: "9:30", "13:15", "1:15 pm".
    /// Without am or pm, 1:00 through 6:59 is read as the afternoon, since the
    /// school day never starts before 7.
    static func parseClockMinute(_ text: String, key: String) throws -> Int {
        let lowered = text.trimmed().lowercased().replacingOccurrences(of: " ", with: "")
        var body = lowered
        var suffix = ""
        for tail in ["am", "pm"] where lowered.hasSuffix(tail) {
            body = String(lowered.dropLast(2))
            suffix = tail
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            throw MCPToolError("\(key) must be a time like 9:30 or 1:15, got \"\(text)\".")
        }
        var wrapped = hour
        if suffix == "pm", hour < 12 { wrapped += 12 }
        if suffix == "am", hour == 12 { wrapped = 0 }
        if suffix.isEmpty, (1...6).contains(hour) { wrapped += 12 }
        return wrapped * 60 + minute
    }

    /// The children named, as the student ID strings a block stores. A first
    /// name two children share throws, asking for the full name.
    static func timetableChildren(
        _ names: [String], in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        try names.map { name in
            let student = try resolveStudentReference(name, in: modelContext)
            guard let id = student.id else { throw MCPToolError("\(student.fullName) has no saved identifier.") }
            return id.uuidString
        }
    }

    /// A block's values from a tool call's fields; `base` supplies whatever isn't given.
    static func timetableValues(
        from arguments: [String: JSONValue],
        base: TimetableBlockValues?,
        lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> TimetableBlockValues {
        var values = base ?? TimetableBlockValues(startMinute: 0)
        let start = try nonEmpty(arguments["start"]?.stringValue).map { try parseClockMinute($0, key: "start") }
        if let start { values.startMinute = start }
        if let length = arguments["length_minutes"]?.intValue {
            guard (1...720).contains(length) else {
                throw MCPToolError("length_minutes must be between 1 and 720.")
            }
            values.lengthMinutes = length
        } else if let end = try nonEmpty(arguments["end"]?.stringValue).map({ try parseClockMinute($0, key: "end") }) {
            guard end > values.startMinute else { throw MCPToolError("end must be after start.") }
            values.lengthMinutes = end - values.startMinute
        } else if base == nil {
            throw MCPToolError("Give length_minutes or end for each block.")
        }
        if base == nil, start == nil { throw MCPToolError("Give a start time for each block.") }
        if let title = arguments["title"]?.stringValue { values.title = title.trimmed() }
        if let note = arguments["note"]?.stringValue { values.note = note.trimmed() }
        if let teacher = arguments["teacher"]?.stringValue {
            let name = teacher.trimmed()
            let person = name.isEmpty ? nil : lanes.first {
                $0.kind == .person && $0.name.foldedKey() == name.foldedKey()
            }
            values.teacherLaneID = person?.id
            values.teacherName = person == nil ? name : ""
        }
        if arguments["children"] != nil {
            values.studentIDs = try timetableChildren(stringArrayArgument(arguments, "children"), in: modelContext)
        }
        return values
    }
}
