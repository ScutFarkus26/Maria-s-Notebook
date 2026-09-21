//
//  MCPNotebookTools+SchoolCalendarWrites.swift
//  Cosmic Daybook
//
//  The two school-calendar writes: marking days no school (or back in
//  session) and changing the school-year settings. The read half is in
//  MCPNotebookTools+SchoolCalendar.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Set Days

    static func setSchoolDaysTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "set_school_days",
            title: "Set School Days",
            description: "Mark days as no school (the default) or back in session, the same "
                + "change as tapping them on the Settings calendar. Pass one date, a dates "
                + "list, or a from/to range; a range skips weekends unless include_weekends "
                + "is true. A weekend set in_session becomes a school day. Already-set days "
                + "are left alone, so calling twice is safe.",
            inputSchema: setSchoolDaysSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try setSchoolDays(arguments: arguments, in: context())
            }
        )
    }

    private static let setSchoolDaysSchema: JSONValue = [
        "type": "object",
        "properties": [
            "date": [
                "type": "string",
                "description": "One day, YYYY-MM-DD"
            ],
            "dates": [
                "type": "array",
                "description": "Several days, each YYYY-MM-DD",
                "items": ["type": "string"]
            ],
            "from": [
                "type": "string",
                "description": "First day of a range, YYYY-MM-DD (with to)"
            ],
            "to": [
                "type": "string",
                "description": .string("Last day of a range, YYYY-MM-DD, inclusive (with from); at most "
                    + "a year")
            ],
            "in_session": [
                "type": "boolean",
                "description": .string("false (default) marks the days no school; true makes them "
                    + "school days again")
            ],
            "reason": [
                "type": "string",
                "description": .string("Why school is out, e.g. Thanksgiving, Winter break, Teacher "
                    + "planning day (no-school days only)")
            ],
            "include_weekends": [
                "type": "boolean",
                "description": .string("Apply a from/to range to its Saturdays and Sundays too "
                    + "(default false)")
            ]
        ]
    ]

    /// What one call did, day by day, for the receipt.
    private struct SchoolDayTally {
        var changed: [Date] = []
        var reasonUpdated: [Date] = []
        var unchanged: [Date] = []

        var wroteSomething: Bool { !changed.isEmpty || !reasonUpdated.isEmpty }

        mutating func record(_ change: SchoolCalendarService.SchoolDayChange, on day: Date) {
            switch change {
            case .markedNonSchool, .markedSchool: changed.append(day)
            case .reasonUpdated: reasonUpdated.append(day)
            case .unchanged: unchanged.append(day)
            }
        }

        func lines(state: String, reason: String?) -> [String] {
            var lines: [String] = []
            if !changed.isEmpty {
                let reasonText = reason.map { " — \($0)" } ?? ""
                lines.append("Marked \(MCPNotebookTools.dayList(changed)) \(state)\(reasonText).")
            }
            if !reasonUpdated.isEmpty {
                lines.append("Updated the reason on \(MCPNotebookTools.dayList(reasonUpdated)), already no school.")
            }
            if !unchanged.isEmpty {
                lines.append("Already \(state): \(MCPNotebookTools.dayList(unchanged)).")
            }
            return lines
        }
    }

    private static func setSchoolDays(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let inSession = arguments["in_session"]?.boolValue ?? false
        let reason = nonEmpty(arguments["reason"]?.stringValue)
        if inSession, reason != nil {
            throw MCPToolError("reason describes a no-school day; leave it off when in_session is true.")
        }
        let days = try requestedDays(arguments)
        guard !days.isEmpty else {
            throw MCPToolError("No days to set — pass date, dates, or from and to.")
        }

        var tally = SchoolDayTally()
        do {
            for day in days {
                let change = try SchoolCalendarService.shared.setSchoolDay(
                    day, inSession: inSession, reason: reason, using: modelContext
                )
                tally.record(change, on: day)
            }
        } catch {
            modelContext.rollback()
            throw MCPToolError("The calendar could not be read: \(error.localizedDescription)")
        }
        if tally.wroteSomething, !modelContext.safeSave() {
            modelContext.rollback()
            throw MCPToolError("The calendar change could not be saved.")
        }
        return tally.lines(state: inSession ? "in session" : "no school", reason: reason)
            .joined(separator: "\n")
    }

    /// The days named by `date`, `dates`, and `from`/`to`, each at start of
    /// day, deduplicated, in order. Every value parses before any is used.
    private static func requestedDays(_ arguments: [String: JSONValue]) throws -> [Date] {
        var days: [Date] = []
        if let single = try dayArgument(arguments, "date") {
            days.append(AppCalendar.startOfDay(single))
        }
        for (index, text) in stringArrayArgument(arguments, "dates").enumerated() {
            guard let parsed = isoDay.date(from: text) else {
                throw MCPToolError("dates[\(index)] must be formatted YYYY-MM-DD, got \"\(text)\".")
            }
            days.append(AppCalendar.startOfDay(parsed))
        }
        days.append(contentsOf: try rangeDays(arguments))
        var seen: Set<Date> = []
        return days.filter { seen.insert($0).inserted }
    }

    /// Every day of the `from`…`to` range, weekends left out unless
    /// `include_weekends`; empty when neither bound is given.
    private static func rangeDays(_ arguments: [String: JSONValue]) throws -> [Date] {
        let from = try dayArgument(arguments, "from")
        let to = try dayArgument(arguments, "to")
        guard from != nil || to != nil else { return [] }
        guard let from, let to else { throw MCPToolError("from and to go together.") }
        let start = AppCalendar.startOfDay(from)
        let end = AppCalendar.startOfDay(to)
        guard start <= end else { throw MCPToolError("from must be on or before to.") }
        let span = AppCalendar.shared.dateComponents([.day], from: start, to: end).day ?? 0
        guard span <= 366 else {
            throw MCPToolError("A range can cover at most a year; split it into two calls.")
        }
        let includeWeekends = arguments["include_weekends"]?.boolValue ?? false
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            if includeWeekends || !isWeekend(cursor) { days.append(cursor) }
            guard let next = AppCalendar.shared.date(byAdding: .day, value: 1, to: cursor),
                  next > cursor else { break }
            cursor = next
        }
        return days
    }

    static func dayList(_ days: [Date]) -> String {
        let sorted = days.sorted()
        if sorted.count > 6, let first = sorted.first, let last = sorted.last {
            return "\(sorted.count) days from \(dayString(first)) to \(dayString(last))"
        }
        return sorted.map { dayString($0) }.joined(separator: ", ")
    }

    // MARK: - Year Settings

    static func updateSchoolCalendarTool(
        dependencies: @escaping MCPDependenciesProvider
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_school_calendar",
            title: "Update School Calendar Settings",
            description: "Change the school-year settings in Settings › School Calendar: the "
                + "month and day the year starts on, and whether day counters (days since "
                + "last lesson, meeting, work aging) start over on that day or run over all "
                + "history. Moving the start re-buckets which year past activity falls into; "
                + "it never moves or deletes data. To mark days no school use set_school_days.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "start_month": [
                        "type": "integer",
                        "description": "Month the school year starts, 1-12"
                    ],
                    "start_day": [
                        "type": "integer",
                        "description": "Day of that month, 1-31 (clamped to the month's last day)"
                    ],
                    "counters_reset_at_year_start": [
                        "type": "boolean",
                        "description": .string("true: day counters start over on the first day of the "
                            + "current school year; false: they run over all history")
                    ]
                ]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                guard let container = dependencies() else {
                    throw MCPToolError("The app is still starting; settings are not available yet.")
                }
                return try updateSchoolCalendar(arguments: arguments, store: container.schoolYearStore)
            }
        )
    }

    private static func updateSchoolCalendar(
        arguments: [String: JSONValue], store: SchoolYearStore
    ) throws -> String {
        let month = arguments["start_month"]?.intValue
        let day = arguments["start_day"]?.intValue
        let resetCounters = arguments["counters_reset_at_year_start"]?.boolValue
        guard month != nil || day != nil || resetCounters != nil else {
            throw MCPToolError(
                "Nothing to change — pass start_month, start_day, or counters_reset_at_year_start."
            )
        }
        if let month, !(1...12).contains(month) {
            throw MCPToolError("start_month must be 1-12, got \(month).")
        }
        if let day, !(1...31).contains(day) {
            throw MCPToolError("start_day must be 1-31, got \(day).")
        }

        let before = SchoolYearSettings(store: store)
        let changes = applySchoolYearSettings(
            month: month, day: day, resetCounters: resetCounters, to: store
        )
        let after = SchoolYearSettings(store: store)

        var lines: [String] = []
        if changes.isEmpty {
            lines.append("The school calendar already had those settings.")
        } else {
            lines.append("Updated \(changes.joined(separator: ", ")).")
        }
        lines.append(contentsOf: after.lines)
        if before.currentYear != after.currentYear, store.isResettingCounters,
           store.counterEpoch != after.currentYear.start {
            lines.append(
                "Day counters still start over on \(dayString(store.counterEpoch)); call again "
                    + "with counters_reset_at_year_start true to move them to "
                    + "\(dayString(after.currentYear.start))."
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Writes only the settings that differ, naming each one it changed.
    private static func applySchoolYearSettings(
        month: Int?, day: Int?, resetCounters: Bool?, to store: SchoolYearStore
    ) -> [String] {
        var changes: [String] = []
        if let month, month != store.startMonth {
            store.startMonth = month
            changes.append("start month")
        }
        if let day, day != store.startDay {
            store.startDay = day
            changes.append("start day")
        }
        if let resetCounters, resetCounters != store.isResettingCounters {
            store.setCountersResetAtYearStart(resetCounters)
            changes.append("day counters")
        }
        return changes
    }
}
