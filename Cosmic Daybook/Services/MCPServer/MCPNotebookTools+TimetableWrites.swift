//
//  MCPNotebookTools+TimetableWrites.swift
//  Cosmic Daybook
//
//  Entering a timetable and changing one day of it, so a pasted or
//  photographed schedule can be typed in for the guide.
//
//  Both go through `TimetableService`, the one writer the Schedules page uses,
//  and save on the view context so `SharedStoreOrphanGuard` puts new rows into
//  the classroom share. `set_timetable` is confirm-gated: it ends the lane's
//  running weekly blocks, so it reports first and writes on `confirm: true`.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Set Timetable

    static func setTimetableTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "set_timetable",
            title: "Set Timetable",
            description: "Replace one lane's weekly blocks from a day on, This Day and After style: the "
                + "lane's running weekly blocks end the day before (weeks already past still read as they "
                + "were), and the blocks given start on that day. One-offs stay. Called without confirm it "
                + "only reports what would end and what would start; nothing is written until it is "
                + "called again with confirm: true. Each block names its weekdays, a start time, a length "
                + "or an end, a title, and optionally a note, who teaches it, and the children by name. "
                + "Times are school times: 9:30, 1:15 (1:00 to 6:59 without am or pm is the afternoon). "
                + "A first name two children share needs the full name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lane": [
                        "type": "string",
                        "description": "The lane by name or id, as weekly_schedules shows it"
                    ],
                    "from": [
                        "type": "string",
                        "description": "The first day the new week applies, YYYY-MM-DD. Default today"
                    ],
                    "blocks": [
                        "type": "array",
                        "description": "The lane's whole new week. An empty list leaves the lane with no weekly blocks",
                        "items": blockFields(including: ["weekdays": [
                            "type": "array",
                            "items": ["type": "string"],
                            "minItems": 1,
                            "description": "Full weekday names, e.g. [\"Monday\", \"Wednesday\"]"
                        ]])
                    ],
                    "create_lane": [
                        "type": "boolean",
                        "description": "Make a new person lane with this name when none matches (Morah Devora)"
                    ],
                    "confirm": [
                        "type": "boolean",
                        "description": "Pass true, after reading the report, to replace the week"
                    ]
                ],
                "required": ["lane", "blocks"]
            ],
            annotations: .destructive,
            handler: { arguments in
                try undoingOnFailure(context()) { try setTimetable(arguments: arguments, in: $0) }
            }
        )
    }

    /// The fields a block takes, shared by set_timetable's items and change_schedule_day.
    private static func blockFields(including extra: [String: JSONValue] = [:]) -> JSONValue {
        var properties: [String: JSONValue] = [
            "start": ["type": "string", "description": "Start time, e.g. 9:30 or 1:15"],
            "length_minutes": ["type": "integer", "description": "Length in minutes (or give end)"],
            "end": ["type": "string", "description": "End time (or give length_minutes)"],
            "title": ["type": "string", "description": "What the block is"],
            "note": ["type": "string", "description": "An optional note"],
            "teacher": [
                "type": "string",
                "description": "Who teaches it: a person lane's name (Danny, Morah Devora) or any typed name"
            ],
            "children": [
                "type": "array",
                "items": ["type": "string"],
                "description": "The children in it, by name"
            ]
        ]
        for (key, value) in extra { properties[key] = value }
        return ["type": "object", "properties": .object(properties)]
    }

    private static func setTimetable(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "lane")
        let calendar = AppCalendar.shared
        let from = try calendar.startOfDay(for: dayArgument(arguments, "from") ?? Date())
        guard let specs = arguments["blocks"]?.arrayValue else {
            throw MCPToolError("Missing required argument: blocks")
        }
        var lanes = TimetableService.lanes(in: modelContext)
        let matches = matchingTimetableLanes(reference, in: lanes)
        let creating = matches.isEmpty && arguments["create_lane"]?.boolValue == true
        let existing = creating ? nil : try timetableLane(reference, in: lanes)

        // Everything is read before anything is written, so a bad block fails whole.
        var week: [TimetableService.WeeklyBlock] = []
        for (index, spec) in specs.enumerated() {
            guard let fields = spec.objectValue else { throw MCPToolError("Block \(index + 1) is not an object.") }
            let days = (fields["weekdays"]?.arrayValue ?? []).compactMap(\.stringValue)
                + (fields["weekday"]?.stringValue.map { [$0] } ?? [])
            guard !days.isEmpty else { throw MCPToolError("Block \(index + 1) needs weekdays.") }
            let values: TimetableBlockValues
            do {
                values = try timetableValues(from: fields, base: nil, lanes: lanes, in: modelContext)
            } catch let error as MCPToolError {
                throw MCPToolError("Block \(index + 1): \(error.message)")
            }
            var seen = Set<Weekday>()
            for weekday in try days.map(parseWeekday) where seen.insert(weekday).inserted {
                week.append(TimetableService.WeeklyBlock(weekday: weekday, values: values))
            }
        }
        week.sort { lhs, rhs in
            let left = Weekday.allCases.firstIndex(of: lhs.weekday) ?? 0
            let right = Weekday.allCases.firstIndex(of: rhs.weekday) ?? 0
            return left != right ? left < right : lhs.values.startMinute < rhs.values.startMinute
        }

        let laneName = existing?.name ?? reference
        let running = existing.map { lane in
            TimetableService.blocks(of: lane, in: modelContext).filter {
                !$0.isOneOff && TimetableService.isRunning($0, onOrAfter: from, calendar: calendar)
            }.count
        } ?? 0
        let when = "\(weekdayName(from)) \(dayString(from))"
        let names = studentNameIndex(in: modelContext)

        guard arguments["confirm"]?.boolValue == true else {
            MCPCallOutcome.markNothingWritten()
            var lines = [
                "set_timetable refused — nothing has been changed.",
                "Re-call with confirm: true to replace \(laneName)'s week from \(when)."
                    + (creating ? " There is no lane by that name, so a new person lane would be made." : ""),
                "\(running) running weekly block\(running == 1 ? "" : "s") would end the day before "
                    + "(weeks already past keep them); \(week.count) would start.",
                "", "The new week:"
            ]
            lines.append(contentsOf: week.map {
                "- \($0.weekday.rawValue) \(TimetableDay.rangeText($0.values)) "
                    + (nonEmpty($0.values.title) ?? "Untitled")
                    + (previewKids($0.values, names: names))
            })
            return lines.joined(separator: "\n")
        }

        if lanes.isEmpty { lanes = TimetableService.makeStarterLanes(in: modelContext) }
        let lane = existing ?? TimetableService.addPerson(named: reference, in: modelContext)
        TimetableService.replaceWeek(of: lane, with: week, from: from, in: modelContext)
        guard modelContext.safeSave() else {
            throw MCPToolError("The timetable could not be saved.")
        }
        let days = Set(week.map(\.weekday)).count
        return "Set [lane id=\(lane.id?.uuidString ?? "unknown")] \(lane.name)'s week from \(when): "
            + "\(week.count) block\(week.count == 1 ? "" : "s") on \(days) day\(days == 1 ? "" : "s"); "
            + "\(running) earlier block\(running == 1 ? "" : "s") end the day before."
    }

    private static func previewKids(_ values: TimetableBlockValues, names: [String: String]) -> String {
        guard !values.studentIDs.isEmpty else { return "" }
        return " — with " + values.studentIDs.map { names[$0.uppercased()] ?? "a child" }.joined(separator: ", ")
    }

    // MARK: - Change a Day

    static func changeScheduleDayTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "change_schedule_day",
            title: "Change Schedule Day",
            description: "Change one day of the Schedules timetables, without touching the other weeks. "
                + "action is one of: cancel (a block that day; a one-off is removed), change (a block's "
                + "start, length or end, title, note, teacher or children for that day only), add (a "
                + "one-off block in a lane: an assembly, a trip, an early dismissal), out (a person is "
                + "out that day: their blocks go and their turns in a room read Out), back_in (undo out), "
                + "undo (take away one block's change, or with no block every change that day; that "
                + "one needs confirm: true). Name a block by block_id from weekly_schedules, or by lane "
                + "plus its start and/or part of its title. Refuses a day with no school. For a new "
                + "timetable from a day on, use set_timetable.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "date": ["type": "string", "description": "The day, YYYY-MM-DD"],
                    "action": [
                        "type": "string",
                        "enum": ["cancel", "change", "add", "out", "back_in", "undo"]
                    ],
                    "lane": [
                        "type": "string",
                        "description": "The lane, by name or id (needed for add, out and back_in)"
                    ],
                    "block_id": ["type": "string", "description": "The block's id from weekly_schedules"],
                    "block_start": ["type": "string", "description": "Finds a block in the lane by its start time"],
                    "block_title": ["type": "string", "description": "Finds a block in the lane by part of its title"],
                    "start": ["type": "string", "description": "Start time, e.g. 9:30 or 1:15"],
                    "length_minutes": ["type": "integer", "description": "Length in minutes (or give end)"],
                    "end": ["type": "string", "description": "End time (or give length_minutes)"],
                    "title": ["type": "string", "description": "A block's title (required for add)"],
                    "note": ["type": "string", "description": "An optional note"],
                    "teacher": [
                        "type": "string",
                        "description": "Who teaches it: a person lane's name or any typed name"
                    ],
                    "children": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "The children in it, by name. For change this replaces the block's children"
                    ],
                    "confirm": [
                        "type": "boolean",
                        "description": "Pass true to undo every change on the day"
                    ]
                ],
                "required": ["date", "action"]
            ],
            annotations: .write,
            handler: { arguments in
                try undoingOnFailure(context()) { try changeScheduleDay(arguments: arguments, in: $0) }
            }
        )
    }

    private static func changeScheduleDay(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let requested = try dayArgument(arguments, "date") else {
            throw MCPToolError("A date is required, formatted YYYY-MM-DD.")
        }
        let calendar = AppCalendar.shared
        let day = calendar.startOfDay(for: requested)
        let lanes = TimetableService.lanes(in: modelContext)
        guard !lanes.isEmpty else { throw MCPToolError("No timetable is set up yet. Use set_timetable first.") }
        let action = try requireString(arguments, "action").foldedKey()
        let when = "\(weekdayName(day)) \(dayString(day))"

        let receipt: String
        switch action {
        case "cancel", "change", "add", "out", "back_in":
            guard !SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext) else {
                throw MCPToolError("School is not in session on \(dayString(day)) (\(weekdayName(day))); "
                    + "nothing was changed. Choose a school day.")
            }
            switch action {
            case "cancel": receipt = try cancelBlock(arguments, on: day, lanes: lanes, in: modelContext)
            case "change": receipt = try changeBlock(arguments, on: day, lanes: lanes, in: modelContext)
            case "add": receipt = try addOneOff(arguments, on: day, lanes: lanes, in: modelContext)
            default:
                receipt = try setOut(action == "out", arguments, on: day, lanes: lanes, in: modelContext)
            }
        case "undo":
            guard let text = try undoDay(arguments, on: day, lanes: lanes, in: modelContext) else {
                return try undoPreview(on: day, in: modelContext)
            }
            receipt = text
        default:
            throw MCPToolError("action must be cancel, change, add, out, back_in or undo, got \"\(action)\".")
        }
        guard modelContext.safeSave() else {
            throw MCPToolError("The schedule change could not be saved.")
        }
        return receipt.replacingOccurrences(of: "{when}", with: when)
    }

    // MARK: Blocks

    private static func cancelBlock(
        _ arguments: [String: JSONValue], on day: Date, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> String {
        let block = try timetableBlock(arguments, on: day, lanes: lanes, in: modelContext)
        let label = blockLabel(block)
        TimetableService.cancel(block, on: day, in: modelContext)
        return block.isDeleted
            ? "Removed the one-off \(label) on {when}."
            : "Cancelled \(label) on {when} only. [block id=\(block.id?.uuidString ?? "unknown")]"
    }

    private static func changeBlock(
        _ arguments: [String: JSONValue], on day: Date, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> String {
        let fields = ["start", "length_minutes", "end", "title", "note", "teacher", "children"]
        guard fields.contains(where: { arguments[$0] != nil }) else {
            throw MCPToolError("Say what changes: start, length_minutes or end, title, note, teacher or children.")
        }
        let block = try timetableBlock(arguments, on: day, lanes: lanes, in: modelContext)
        // A change already made that day is the starting point, so changing the
        // title doesn't undo an earlier change of time.
        let current = TimetableService.changes(of: block, on: day, in: modelContext)
            .filter { $0.kind == .changed }
            .max { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }?.values
        let values = try timetableValues(
            from: arguments, base: current ?? block.values, lanes: lanes, in: modelContext
        )
        let before = blockLabel(block)
        TimetableService.edit(block, to: values, scope: .onlyThisDay, on: day, in: modelContext)
        return "Changed \(before) on {when} only: now \(TimetableDay.rangeText(values)) "
            + "\(nonEmpty(values.title) ?? "Untitled"). [block id=\(block.id?.uuidString ?? "unknown")]"
    }

    private static func addOneOff(
        _ arguments: [String: JSONValue], on day: Date, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lane = try timetableLane(requireString(arguments, "lane"), in: lanes)
        guard nonEmpty(arguments["title"]?.stringValue) != nil else {
            throw MCPToolError("A one-off needs a title.")
        }
        let values = try timetableValues(from: arguments, base: nil, lanes: lanes, in: modelContext)
        guard let block = TimetableService.addOneOff(values, to: lane, on: day, in: modelContext) else {
            throw MCPToolError("That lane has no saved identifier.")
        }
        return "Added \(TimetableDay.rangeText(values)) \(values.title) to \(lane.name) on {when} only. "
            + "[block id=\(block.id?.uuidString ?? "unknown")]"
    }

    private static func setOut(
        _ isOut: Bool, _ arguments: [String: JSONValue], on day: Date, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lane = try timetableLane(requireString(arguments, "lane"), in: lanes)
        guard lane.kind == .person else {
            throw MCPToolError("\(lane.name) is a room. Out applies to a person's lane.")
        }
        let already = TimetableService.isOut(lane, on: day, in: modelContext)
        guard already != isOut else {
            MCPCallOutcome.markNothingWritten()
            return isOut ? "\(lane.name) was already out on {when}." : "\(lane.name) was not out on {when}."
        }
        TimetableService.setOut(lane, isOut, on: day, in: modelContext)
        return isOut
            ? "\(lane.name) is out on {when}: their blocks are off and their turns read Out."
            : "\(lane.name) is back in on {when}."
    }

    // MARK: Undo

    /// The receipt, or nil when the whole day's undo still needs `confirm`.
    private static func undoDay(
        _ arguments: [String: JSONValue], on day: Date, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> String? {
        if arguments["block_id"] != nil || arguments["block_title"] != nil || arguments["block_start"] != nil {
            let block = try timetableBlock(arguments, on: day, lanes: lanes, in: modelContext)
            guard !block.isOneOff else {
                throw MCPToolError("That block is a one-off, not a change to a weekly one. Use cancel to remove it.")
            }
            guard !TimetableService.changes(of: block, on: day, in: modelContext).isEmpty else {
                MCPCallOutcome.markNothingWritten()
                return "\(blockLabel(block)) had no change on {when}."
            }
            TimetableService.undoChanges(to: block, on: day, in: modelContext)
            return "Took away the change to \(blockLabel(block)) on {when}; it reads as every week."
        }
        guard arguments["confirm"]?.boolValue == true else { return nil }
        let count = TimetableService.changes(from: day, through: day, in: modelContext).count
        guard count > 0 else {
            MCPCallOutcome.markNothingWritten()
            return "Nothing was changed on {when}."
        }
        TimetableService.undoAllChanges(on: day, in: modelContext)
        return "Took away \(count) change\(count == 1 ? "" : "s") on {when}, people out included. "
            + "One-off blocks stay; cancel removes one."
    }

    private static func undoPreview(on day: Date, in modelContext: NSManagedObjectContext) throws -> String {
        MCPCallOutcome.markNothingWritten()
        let count = TimetableService.changes(from: day, through: day, in: modelContext).count
        let when = "\(weekdayName(day)) \(dayString(day))"
        guard count > 0 else { return "Nothing was changed on \(when)." }
        return "change_schedule_day refused — nothing has been changed.\n"
            + "Re-call with confirm: true to take away all \(count) change\(count == 1 ? "" : "s") on \(when), "
            + "or name one block to undo only its change."
    }

    // MARK: Finding a block

    /// The block named by `block_id`, or in `lane` (as its own or as the one
    /// teaching it) at `block_start` and/or with `block_title` in its title,
    /// among those that apply on `day`.
    private static func timetableBlock(
        _ arguments: [String: JSONValue], on day: Date, lanes: [CDTimetableLane],
        in modelContext: NSManagedObjectContext
    ) throws -> CDTimetableBlock {
        let all = TimetableService.blocks(in: modelContext)
        if let reference = nonEmpty(arguments["block_id"]?.stringValue) {
            guard let id = UUID(uuidString: reference), let block = all.first(where: { $0.id == id }) else {
                throw MCPToolError("No block with id \(reference). weekly_schedules shows the ids.")
            }
            return block
        }
        let lane = try timetableLane(requireString(arguments, "lane"), in: lanes)
        let start = try nonEmpty(arguments["block_start"]?.stringValue).map { try parseClockMinute($0, key: "block_start") }
        let title = nonEmpty(arguments["block_title"]?.stringValue)?.foldedKey()
        guard start != nil || title != nil else {
            throw MCPToolError("Name the block: block_id, or block_start and/or block_title with the lane.")
        }
        let calendar = AppCalendar.shared
        let candidates = all.filter { block in
            guard block.laneID.caseInsensitiveCompare(lane.id?.uuidString ?? "") == .orderedSame
                || block.teacherLaneID?.caseInsensitiveCompare(lane.id?.uuidString ?? "") == .orderedSame,
                let snapshot = TimetableBlockSnapshot(block),
                ScheduleDayResolver.applies(snapshot, on: day, calendar: calendar) else { return false }
            if let start, Int(block.startMinute) != start { return false }
            if let title, !block.title.foldedKey().contains(title) { return false }
            return true
        }
        if candidates.count == 1, let block = candidates.first { return block }
        let when = "\(weekdayName(day)) \(dayString(day))"
        if candidates.isEmpty {
            throw MCPToolError("No block of \(lane.name) matches on \(when). weekly_schedules with date shows the day.")
        }
        let list = candidates.map { "\(blockLabel($0)) [block id=\($0.id?.uuidString ?? "unknown")]" }
        throw MCPToolError("More than one block of \(lane.name) matches on \(when): "
            + list.joined(separator: "; ") + ". Pass block_id.")
    }

    private static func blockLabel(_ block: CDTimetableBlock) -> String {
        "\(TimetableDay.rangeText(block.values)) \(nonEmpty(block.title) ?? "Untitled")"
    }
}
